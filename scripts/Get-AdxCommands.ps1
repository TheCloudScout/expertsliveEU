<#

    .DESCRIPTION
    This script will generate ADX commands based on sample files to determine their schema.
    These sample files should be in a proper JSON format and contain a single object.

    .PARAMETER TemplateFolder <String>
    Location which contains the sample files

#>

[CmdletBinding()]
param (
    [Parameter (Mandatory = $true)]
    [String] $sampleFileDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Clear-Host

If (!(Test-Path $sampleFileDirectory)) {
    Write-Host " ✘ Couldn't read $($sampleFileDirectory) or path not found!" -ForegroundColor Red
    Write-Host ""
    exit
}

$sampleFiles    = @()  
$sampleFiles   += $sampleFileDirectory | Get-ChildItem | Select-Object -ExpandProperty Name

Write-Host "Found $($sampleFiles.Count) sample files in $($sampleFileDirectory)" -ForegroundColor DarkGreen

$adxCommands    = @()

foreach ($sample in $sampleFiles) {
    Write-Host ""
    Write-Host "Processing sample file '$sample'..." -ForegroundColor Cyan
    $adxTableName           = $sample.Replace('.json','').Replace('_Sample', '').Replace('_sample', '').Replace('Sample','').Replace('sample','') + "_CL_Raw"
    $adxTableMappingName    = $adxTableName.Replace('_','').ToLower() + "_mapping"
    Write-Host ""
    Write-Host "      ADX table name          : $adxTableName" -ForegroundColor DarkGray
    Write-Host "      ADX tableMapping name   : $adxTableMappingName" -ForegroundColor DarkGray

    $adxSchema = @()

    $sampleContents = (Get-Content $sampleFileDirectory/$sample -Raw | ConvertFrom-Json)[0]

    $sampleContentColumnNames = $sampleContents | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    Write-Host "      ADX table colums        : $($sampleContentColumnNames.Count)" -ForegroundColor DarkGray

    Foreach ($column in $sampleContentColumnNames) { 
        # Construct new hash table with information about this workspace
        switch ($sampleContents.$column.GetType().Name) {
            "DateTime"  { $ColumnType = "datetime" }
            "String"    { $ColumnType = "string" }
            "Object[]"  { $ColumnType = "dynamic" }
            "Int32"     { $ColumnType = "int" }
            "Int64"     { $ColumnType = "int" }
            default     { $ColumnType = "string" } # else
        }
        
        $sampleProperty = New-Object PSObject -property @{
            ColumnName  = $column.Replace("@", "ls_");
            DataType    = $ColumnType
            Path        = $column
        }
        $adxSchema     += $sampleProperty
    }

    Write-Host ""
    Write-Host "      Generating ADX commands..."
    
    # Construct table creation command
    # Add first part of ADX command into variable
    $createTable = ".create table $adxTableName ( "
    # Add all column names and datatypes to variable
    Foreach ($column in $adxSchema) {
        $createTable   += $column.ColumnName + ": " + $column.DataType + ", "
    }
    # Remove last comma and space
    $createTable = $createTable.substring(0, $createTable.length -2)
    # Add last part of ADX command into variable
    $createTable       += " )"
    
    # Construct table mapping creation command
    $createTableMapping = ".create-or-alter table $adxTableName ingestion json mapping '$adxTableMappingName' '[ "
    # Add all column names and datatypes to variable
    Foreach ($column in $adxSchema) {
        $createTableMapping += "{ `"column`": `"" + $column.ColumnName + "`", `"path`": `"$[\'" + $($column).Path + "\']`", `"datatype`": `"`", `"transform`": null }, "
    }
    # Remove last comma and space
    $createTableMapping = $createTableMapping.substring(0, $createTableMapping.length -2)
    # Add last part of ADX command into variable
    $createTableMapping     += " ]`'"

    $adxCommand = New-Object PSObject -property @{                                                                                
        sample                  = $sample;
        adxTableCommand         = $createTable;
        adxTableMappingCommand  = $createTableMapping
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
    Write-Host $adxCommand.adxTableMappingCommand -ForegroundColor DarkMagenta
    Write-Host ""
}
