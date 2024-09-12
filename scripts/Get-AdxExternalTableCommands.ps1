<#
    Koos Goossens 2024
    
    .DESCRIPTION
    Use this script to retrieve the latest blob from the Azure platform logs storage account and generate the ADX external table creation commands.
    
    Make sure to login to Azure using Connect-AzAccount before running this script.

    .PARAMETER subscriptionId [string]
    Provide the Azure Subscription ID in which the storage account is located.
    .PARAMETER storageAccountName [string]
    Provide the name of the storage account where the Azure platform logs are stored. i.e. "starchive01"
    .PARAMETER tempFolder [string]
    Provide the path to a temporary folder where the blob will be downloaded to. i.e. "/Users/koos/temp"

#>

[CmdletBinding()]
param (

    [Parameter (Mandatory = $true)]
    [string] $subscriptionId,

    [Parameter (Mandatory = $true)]
    [string] $storageAccountName,

    [Parameter (Mandatory = $true)]
    [string] $tempFolder

)

# Check if user is logged into Azure
If($null -eq (Get-AzContext)) { 
    Write-Host "" 
    Write-Host "No context found. Please login to Azure using Connect-AzAccount" -ForegroundColor Red
    Write-Host ""
    exit
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Make sure any modules we depend on are installed
$modulesToInstall = @(
    'Az.Storage'
)
Write-Host "Installing/Importing PowerShell modules..." -ForegroundColor DarkGray
$modulesToInstall | ForEach-Object {
    if (-not (Get-Module -ListAvailable -All $_)) {
        Write-Host "Module [$_] not found, installing..." -ForegroundColor DarkGray
        Install-Module $_ -Force
    }
}

$modulesToInstall | ForEach-Object {
    Write-Host "Importing Module [$_]" -ForegroundColor DarkGray
    Import-Module $_ -Force
}


New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

Clear-Host

# Select Azure Subscription
Select-AzSubscription -subscriptionId $subscriptionId | Out-Null

# Set Storage Context for authentication
Write-Host "Processing Storage Account '$storageAccountName'" -ForegroundColor Yellow
$storageContext     = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount

# List Containers containing Azure platform logs
$storageContainers  = $storageContext | Get-AzStorageContainer -Prefix "insights-logs"
Write-Host "Found $(($storageContainers | Measure-Object).Count) containers" -ForegroundColor Yellow

# Loop through containers and download the latest blob
foreach ($container in $storageContainers) {
    Write-Host "Processing container: $($container.Name)" -ForegroundColor DarkCyan
    $storageContext | Get-AzStorageBlob -Container $container.Name -MaxCount 1 | Get-AzStorageBlobContent -Destination $tempFolder -Force  | Out-Null
    # Find downloaded blob and move it to root of temp folder
    $blobFile = (Get-Childitem -Path $tempFolder -Include PT*.json -File -Recurse -ErrorAction SilentlyContinue).VersionInfo.FileName
    # Move and rename blob file
    Move-Item $blobFile $tempFolder\$($container.Name).json -Force | Out-Null
}

$adxCommands    = @()
$sampleFiles    = @()  
$sampleFiles   += $tempFolder | Get-ChildItem -File | Select-Object -ExpandProperty Name

foreach ($sample in $sampleFiles) {
    Write-Host ""
    Write-Host "Processing sample file '$sample'..." -ForegroundColor Cyan
    $adxTableName           = $sample.Replace('.json','').Replace('insights-logs-', '')
    Write-Host ""
    Write-Host "      ADX table name          : $adxTableName" -ForegroundColor DarkGray

    $adxSchema = @()

    $sampleContents = (Get-Content $tempFolder/$sample | ConvertFrom-Json)[0]

    $sampleContentColumnNames = $sampleContents | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    Write-Host "      ADX table colums        : $($sampleContentColumnNames.Count)" -ForegroundColor DarkGray

    Foreach ($column in $sampleContentColumnNames) { 
        # Construct new hash table with information about this workspace
        switch ($sampleContents.$column.GetType().Name) {
            "DateTime"          { $ColumnType = "datetime" }
            "String"            { $ColumnType = "string" }
            "PSCustomObject"    { $ColumnType = "dynamic" }
            "Int64"             { $ColumnType = "int" }
            default             { $ColumnType = "string" } # else
        }
        
        $sampleProperty = New-Object PSObject -property @{
            ColumnName  = $column
            DataType    = $ColumnType
            Path        = $column
        }
        $adxSchema     += $sampleProperty
    }

    Write-Host ""
    Write-Host "      Generating ADX commands..."
    
    # Construct table creation command
    # Add first part of ADX command into variable
    $createTable = ".create-or-alter external table ['$adxTableName'] ( "
    # Add all column names and datatypes to variable
    Foreach ($column in $adxSchema) {
        $createTable   += "['" + $column.ColumnName + "']" + ":" + $column.DataType + ", "
    }
    # Remove last comma and space
    $createTable = $createTable.substring(0, $createTable.length -2)
    # Add last part of ADX command into variable
    $createTable       += @"
)
    kind = blob
    dataformat = multijson
    (
        h@'https://$storageAccountName.blob.core.windows.net/insights-logs-$adxTableName;impersonate'
    )
    with (FileExtension=json)
"@
    
    $adxCommand = New-Object PSObject -property @{                                                                                
        sample                  = $sample;
        adxTableCommand         = $createTable
    }
    $adxCommands += $adxCommand
}

# Write ADX command to console
Write-Host ""
Write-Host "Generation of ADX commands done!" -ForegroundColor DarkGreen
Write-Host ""
Write-Host "Run the following command in Azure Data Explorer :" -ForegroundColor Cyan
Write-Host ""
foreach ($adxCommand in $adxCommands) {
    Write-Host $adxCommand.adxTableCommand -ForegroundColor DarkMagenta
    Write-Host ""
}

Write-Host "Cleaning up temporary files and directories" -ForegroundColor Yellow
# Cleanup temp folders
# Remove-Item $tempFolder -Recurse -Force