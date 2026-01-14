#!/bin/bash

# ============================================================
# VPS MANAGER OS - INSTALLER
# ============================================================

if [ "$EUID" -ne 0 ]; then
  echo "❌ Por favor, execute como root."
  exit
fi

echo "🔵 Iniciando instalação do VPS Manager OS..."

# 1. Instalar Dependências
echo "📦 Atualizando repositórios e instalando dependências..."
apt-get update -q
apt-get install -y curl git unzip whiptail acl

# Instalar Node.js e PM2 (se não existir)
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
fi

if ! command -v pm2 &> /dev/null; then
    npm install -g pm2
fi

# Instalar Caddy (Servidor Web / Proxy)
if ! command -v caddy &> /dev/null; then
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
fi

# 2. Configurar Estrutura de Diretórios
BASE_DIR="/opt/vps-manager"
mkdir -p "$BASE_DIR/core"
mkdir -p "$BASE_DIR/data"
mkdir -p "$BASE_DIR/logs"
mkdir -p "/etc/caddy/sites"

# Configurar Caddy Global
cat > /etc/caddy/Caddyfile <<EOF
{
    # Configurações globais
}

import /etc/caddy/sites/*
EOF
systemctl restart caddy

# 3. Criar Core Scripts

# --- functions.sh ---
cat > "$BASE_DIR/core/functions.sh" <<'EOF'
#!/bin/bash

DB_FILE="/opt/vps-manager/data/db.txt"
SITES_DIR="/etc/caddy/sites"

# Função para log
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /opt/vps-manager/logs/system.log
}

# Criar App
create_app() {
    APP_NAME=$(whiptail --inputbox "Nome da Aplicação (sem espaços, ex: meuapp):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    # Verificar se usuário existe
    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: O usuário/app '$APP_NAME' já existe." 10 60
        return
    fi

    APP_PORT=$(whiptail --inputbox "Porta interna (ex: 3000):" 10 60 3>&1 1>&2 2>&3)
    APP_DOMAIN=$(whiptail --inputbox "Domínio (ex: app.meusite.com):" 10 60 3>&1 1>&2 2>&3)

    # Confirmação
    if ! whiptail --yesno "Criar app '$APP_NAME' na porta $APP_PORT para $APP_DOMAIN?" 10 60; then
        return
    fi

    # 1. Criar Usuário Linux
    useradd -m -s /bin/bash "$APP_NAME"
    log_action "Usuário $APP_NAME criado."

    # 2. Configurar PM2 Isolado
    # O PM2 armazena dados em .pm2 na home do usuário.
    # Não precisamos fazer nada especial além de garantir que o usuário rode o comando.
    
    # 3. Configurar Proxy Reverso (Caddy)
    cat > "$SITES_DIR/$APP_NAME.caddy" <<CONFIG
$APP_DOMAIN {
    reverse_proxy localhost:$APP_PORT
}
CONFIG
    systemctl reload caddy
    log_action "Proxy configurado para $APP_DOMAIN -> :$APP_PORT"

    # 4. Salvar Metadados
    echo "$APP_NAME|$APP_PORT|$APP_DOMAIN" >> "$DB_FILE"

    whiptail --msgbox "✅ App '$APP_NAME' criado com sucesso!\n\nUsuário: $APP_NAME\nHome: /home/$APP_NAME\nPorta: $APP_PORT" 12 60
}

# Listar Apps
list_apps() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app criado ainda." 10 60
        return
    fi

    LISTA=""
    while IFS='|' read -r name port domain; do
        LISTA="$LISTA $name '$domain (: $port)'"
    done < "$DB_FILE"

    # Hack para whiptail aceitar lista dinâmica
    eval whiptail --title \"Lista de Apps\" --msgbox \"$(cat $DB_FILE)\" 20 60
}

# Entrar no App
enter_app() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app para acessar." 10 60
        return
    fi

    # Construir array para menu
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "Acessar App" --menu "Escolha o app para entrar no terminal:" 20 60 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "🚀 Entrando no ambiente de $CHOICE..."
        echo "💡 Dica: Use 'exit' para voltar ao menu principal."
        echo "-----------------------------------------------------"
        
        # Trocar para o usuário
        su - "$CHOICE"
        
        # Ao sair do su, volta para o loop principal
    fi
}

# Remover App
remove_app() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app para remover." 10 60
        return
    fi

    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "DELETAR APP" --menu "Escolha o app para REMOVER (Irreversível):" 20 60 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --yesno "⚠️ TEM CERTEZA? Isso apagará todos os arquivos de $CHOICE." 10 60; then
            
            # 1. Matar processos do usuário
            pkill -u "$CHOICE"
            
            # 2. Remover usuário e home
            userdel -r "$CHOICE"
            
            # 3. Remover config do Caddy
            rm -f "$SITES_DIR/$CHOICE.caddy"
            systemctl reload caddy
            
            # 4. Atualizar DB (remover linha)
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            
            log_action "App $CHOICE removido."
            whiptail --msgbox "🗑️ App $CHOICE removido com sucesso." 10 60
        fi
    fi
}

# Gerenciar Serviços (Status Global)
manage_services() {
    STATUS_CADDY=$(systemctl is-active caddy)
    whiptail --msgbox "Status dos Serviços Globais:\n\nCaddy (Proxy): $STATUS_CADDY\n\nPara ver processos de um app específico, use a opção 'Entrar no App' e digite 'pm2 status'." 15 60
}
EOF

# --- main.sh ---
cat > "$BASE_DIR/core/main.sh" <<'EOF'
#!/bin/bash

# Carregar funções
source /opt/vps-manager/core/functions.sh

# Loop Infinito do Menu
while true; do
    CHOICE=$(whiptail --title "VPS MANAGER OS" --menu "Gerenciamento de Mini-VPS" 20 70 10 \
    "1" "Criar nova Mini-VPS (App)" \
    "2" "Listar Apps" \
    "3" "Entrar em uma Mini-VPS (Terminal)" \
    "4" "Remover Mini-VPS" \
    "5" "Status dos Serviços" \
    "6" "Shell Administrativo (Root)" \
    "0" "Sair (Logout SSH)" 3>&1 1>&2 2>&3)

    EXIT_STATUS=$?

    if [ $EXIT_STATUS -ne 0 ]; then
        # Se cancelar ou esc, volta ao loop
        continue
    fi

    case $CHOICE in
        1) create_app ;;
        2) list_apps ;;
        3) enter_app ;;
        4) remove_app ;;
        5) manage_services ;;
        6) 
            clear
            echo "⚠️  Você está no Shell Administrativo (Root)."
            echo "Digite 'vps-os' para voltar ao menu."
            break 
            ;;
        0) 
            clear
            exit 0 
            ;;
    esac
done
EOF

# 4. Permissões e Link Simbólico
chmod +x "$BASE_DIR/core/"*.sh
ln -sf "$BASE_DIR/core/main.sh" /usr/local/bin/vps-os

# 5. Configurar Persistência no .bashrc do Root
# Adiciona o comando para abrir o menu ao logar, mas permite sair se falhar
if ! grep -q "vps-os" /root/.bashrc; then
    echo "" >> /root/.bashrc
    echo "# VPS Manager OS Auto-Start" >> /root/.bashrc
    echo "if [ -t 1 ]; then" >> /root/.bashrc
    echo "  /usr/local/bin/vps-os" >> /root/.bashrc
    echo "fi" >> /root/.bashrc
fi

echo "✅ Instalação Concluída!"
echo "Digite 'vps-os' para iniciar ou faça logout/login."
