#!/bin/bash

# ============================================================
# VPS MANAGER OS - INSTALADOR COMPLETO (ALL-IN-ONE)
# ============================================================

# 1. VERIFICAÇÃO DE ROOT
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute como root (sudo su)."
  exit 1
fi

echo "🔵 Iniciando instalação do VPS Manager OS..."

# 2. INSTALAÇÃO DE DEPENDÊNCIAS (CORRIGIDA)
# Removemos 'npm' explícito para evitar conflito com nodejs do nodesource
echo "📦 Instalando dependências..."
apt-get update -q
apt-get install -y curl git unzip whiptail acl debian-keyring debian-archive-keyring apt-transport-https

# Instalar Node.js (Versão LTS)
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Instalar PM2 Globalmente
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
fi

# Instalar Caddy (Proxy Reverso)
if ! command -v caddy &> /dev/null; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
fi

# 3. ESTRUTURA DE DIRETÓRIOS
BASE_DIR="/opt/vps-manager"
rm -rf "$BASE_DIR" # Limpa instalação anterior para garantir atualização
mkdir -p "$BASE_DIR/core"
mkdir -p "$BASE_DIR/data"
mkdir -p "$BASE_DIR/logs"
mkdir -p "/etc/caddy/sites"

# Configuração Global do Caddy
cat > /etc/caddy/Caddyfile <<EOF
{
    # Opções globais
}
import /etc/caddy/sites/*
EOF
systemctl restart caddy

# 4. CRIAÇÃO DOS ARQUIVOS DO SISTEMA

# --- ARQUIVO: functions.sh (Lógica) ---
cat > "$BASE_DIR/core/functions.sh" <<'EOF'
#!/bin/bash

DB_FILE="/opt/vps-manager/data/db.txt"
SITES_DIR="/etc/caddy/sites"

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /opt/vps-manager/logs/system.log
}

create_app() {
    APP_NAME=$(whiptail --inputbox "Nome da Aplicação (sem espaços, ex: api01):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: O usuário '$APP_NAME' já existe." 10 60
        return
    fi

    APP_PORT=$(whiptail --inputbox "Porta interna (ex: 3000):" 10 60 3>&1 1>&2 2>&3)
    APP_DOMAIN=$(whiptail --inputbox "Domínio (ex: app.site.com):" 10 60 3>&1 1>&2 2>&3)

    if ! whiptail --yesno "Criar '$APP_NAME' na porta $APP_PORT para $APP_DOMAIN?" 10 60; then return; fi

    # Criar usuário e home
    useradd -m -s /bin/bash "$APP_NAME"
    
    # Configurar Caddy
    cat > "$SITES_DIR/$APP_NAME.caddy" <<CONFIG
$APP_DOMAIN {
    reverse_proxy localhost:$APP_PORT
}
CONFIG
    systemctl reload caddy

    # Salvar no DB
    echo "$APP_NAME|$APP_PORT|$APP_DOMAIN" >> "$DB_FILE"
    
    whiptail --msgbox "✅ App Criado!\n\nUsuário: $APP_NAME\nHome: /home/$APP_NAME\nPara rodar o app: Entrar na VPS > git clone > pm2 start" 12 60
}

list_apps() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app criado." 10 60
        return
    fi
    # Ler arquivo e formatar para whiptail
    TEXTO=$(cat "$DB_FILE")
    whiptail --title "Apps Ativos" --msgbox "$TEXTO" 20 60
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app disponível." 10 60
        return
    fi

    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "Acessar App" --menu "Escolha o app:" 20 60 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "🚀 Acessando ambiente de: $CHOICE"
        echo "Digite 'exit' para voltar ao menu."
        su - "$CHOICE"
    fi
}

remove_app() {
    if [ ! -s "$DB_FILE" ]; then return; fi
    
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "REMOVER APP" --menu "Escolha para DELETAR:" 20 60 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --yesno "⚠️  Apagar TUDO de $CHOICE?" 10 60; then
            pkill -u "$CHOICE"
            userdel -r "$CHOICE"
            rm -f "$SITES_DIR/$CHOICE.caddy"
            systemctl reload caddy
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            whiptail --msgbox "App removido." 10 60
        fi
    fi
}
EOF

# --- ARQUIVO: manager.sh (Menu Principal) ---
cat > "$BASE_DIR/core/manager.sh" <<'EOF'
#!/bin/bash
source /opt/vps-manager/core/functions.sh

# Loop infinito para manter o menu aberto
while true; do
    CHOICE=$(whiptail --title "VPS MANAGER OS" --menu "Painel de Controle" 20 70 10 \
    "1" "Criar Nova Aplicação" \
    "2" "Listar Aplicações" \
    "3" "Entrar no Terminal da App" \
    "4" "Remover Aplicação" \
    "5" "Shell Administrativo (Root)" \
    "0" "Sair (Logout)" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then continue; fi # Se cancelar, volta pro menu

    case $CHOICE in
        1) create_app ;;
        2) list_apps ;;
        3) enter_app ;;
        4) remove_app ;;
        5) clear; echo "Digite 'vps-manager' para voltar."; break ;;
        0) clear; exit 0 ;;
    esac
done
EOF

# 5. PERMISSÕES E LINKS
chmod +x "$BASE_DIR/core/"*.sh
ln -sf "$BASE_DIR/core/manager.sh" /usr/local/bin/vps-manager

# 6. CONFIGURAR INICIALIZAÇÃO AUTOMÁTICA (PERSISTÊNCIA)
# Remove configuração antiga se existir para evitar duplicatas
sed -i '/vps-manager/d' /root/.bashrc

# Adiciona a nova configuração
echo "" >> /root/.bashrc
echo "# VPS Manager Auto-Start" >> /root/.bashrc
echo "if [ -t 1 ]; then" >> /root/.bashrc
echo "  /usr/local/bin/vps-manager" >> /root/.bashrc
echo "fi" >> /root/.bashrc

echo "✅ Instalação Concluída com Sucesso!"
echo "🚀 Iniciando o sistema agora..."
sleep 2

# 7. INICIAR IMEDIATAMENTE
/usr/local/bin/vps-manager
