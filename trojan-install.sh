#!/bin/bash

read -p "请输入 DOMAIN: " DOMAIN
read -p "请输入 CF_Email: " CF_Email
read -p "请输入 CF_Key: " CF_Key
read -p "请输入 SUPABASE_URL: " SUPABASE_URL
read -p "请输入 SUPABASE_SERVICE_ROLE_KEY: " SUPABASE_SERVICE_ROLE_KEY

sudo apt-get update
sudo apt-get install -y jq

if ! command -v nginx &>/dev/null; then
    sudo apt-get install -y nginx
fi

NGINX_HTML_DIR="/var/www/html"
RELEASE_INFO=$(curl -s "https://api.github.com/repos/kamto7/coming-soon/releases/latest")
BUILD_ZIP_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name=="build.zip").browser_download_url')
curl -s -L -o build.zip "$BUILD_ZIP_URL"
rm -rf "${NGINX_HTML_DIR:?}/*"
unzip build.zip -d "$NGINX_HTML_DIR"
rm build.zip

echo -e "server {\n    listen 2000;\n    return 400;\n}" | sudo tee /etc/nginx/conf.d/listen_2000.conf
sudo systemctl restart nginx

if [ ! -d "$HOME/.acme.sh" ]; then
    export CF_Key=$CF_Key
    export CF_Email=$CF_Email
    curl https://get.acme.sh | sh -s email=$CF_Email
    $HOME/.acme.sh/acme.sh --issue --dns dns_cf -d $DOMAIN
fi

CERT_FILE="$HOME/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer"
KEY_FILE="$HOME/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key"

LOCAL_IP=$(curl -s https://ipinfo.io/ip)

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN%.*.*}" -H "X-Auth-Email: $CF_Email" -H "X-Auth-Key: $CF_Key" -H "Content-Type: application/json" | jq -r '.result[0].id')
RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$DOMAIN" -H "X-Auth-Email: $CF_Email" -H "X-Auth-Key: $CF_Key" -H "Content-Type: application/json" | jq -r '.result[0].id')
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" -H "X-Auth-Email: $CF_Email" -H "X-Auth-Key: $CF_Key" -H "Content-Type: application/json" --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$LOCAL_IP\",\"ttl\":120,\"proxied\":false}"

RANDOM_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c8)

if [ ! -d "$HOME/trojan" ]; then
    if ! command -v unzip &>/dev/null; then
        sudo apt-get install -y unzip
    fi
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases/latest" | jq -r '.tag_name')
    wget https://github.com/p4gefau1t/trojan-go/releases/download/${LATEST_RELEASE}/trojan-go-linux-amd64.zip
    sudo unzip trojan-go-linux-amd64.zip -d $HOME/trojan
    rm trojan-go-linux-amd64.zip
fi

cat >$HOME/trojan/server.json <<EOL
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "${RANDOM_PASSWORD}"
    ],
    "ssl": {
        "cert": "${CERT_FILE}",
        "key": "${KEY_FILE}",
        "fallback_port": 2000
    }
}
EOL

cat >/lib/systemd/system/trojan.service <<-EOF
[Unit]  
Description=trojan  
After=network.target  
   
[Service]  
Type=simple  
PIDFile=$HOME/trojan/trojan.pid
ExecStart=$HOME/trojan -c "$HOME/trojan/server.conf"  
ExecReload=  
ExecStop=$HOME/trojan/trojan  
PrivateTmp=true  
   
[Install]  
WantedBy=multi-user.target
EOF

sudo chmod +x /lib/systemd/system/trojan.service
sudo systemctl start trojan.service
sudo systemctl enable trojan.service

SUBDOMAIN=$(echo "$DOMAIN" | cut -d '.' -f 1)

METADATA=$(
    cat <<EOL
{
  "sni": "${DOMAIN}",
  "udp": true,
  "name": "${SUBDOMAIN}",
  "port": 443,
  "type": "trojan",
  "server": "${DOMAIN}",
  "password": "${RANDOM_PASSWORD}"
}
EOL
)

METADATA_JSON_STRING=$(echo "$METADATA" | jq -r '@json')

curl -X POST "${SUPABASE_URL}/rest/v1/proxies" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates" \
    -d "{ \"id\": \"${SUBDOMAIN}\", \"metadata\": ${METADATA_JSON_STRING} }"

echo "Finished!"