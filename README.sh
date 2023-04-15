# Ladder

## Trojan install

```bash
read -p "Please input shell url: " URL && \ 
wget -O trojan-install.sh $URL && \
chmod +x ./trojan-install.sh && \
./trojan-install.sh && \
rm trojan-install.sh
```