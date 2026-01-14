sudo apt update && \
sudo apt install -y git curl sudo nodejs caddy unzip whiptail && \
# Configurar Caddy Globalmente
sudo bash -c 'cat > /etc/caddy/Caddyfile <<EOF
{
}
import /etc/caddy/sites/*
EOF' && \
sudo systemctl restart caddy && \
# Baixar o programa
sudo curl -o /usr/local/bin/vps-manager https://raw.githubusercontent.com/ogerrva/manager_programas/main/manager_programas.sh && \
sudo chmod +x /usr/local/bin/vps-manager && \
# Configurar Boot Automático
(grep -q "vps-manager" ~/.bashrc || echo 'if [ -t 1 ]; then /usr/local/bin/vps-manager; fi' >> ~/.bashrc) && \
echo "✅ Instalação Completa!" && \
/usr/local/bin/vps-manager
