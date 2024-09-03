wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/elastic.gpg >/dev/null

echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-8.x.list >/dev/null

sudo apt-get update && sudo apt-get install logstash=1:8.14.1-1

sudo apt-mark hold logstash

sudo /usr/share/logstash/bin/logstash-plugin install logstash-output-kusto && sudo /usr/share/logstash/bin/logstash-plugin install microsoft-sentinel-log-analytics-logstash-output-plugin