#!/bin/bash

# ============================================================
# VPS MANAGER OS - PRO EDITION (Dark Theme)
# ============================================================

# --- TEMA DARK (Hacker Style) ---
export NEWT_COLORS='
root=,black
window=,black
border=green,black
shadow=,black
title=green,black
button=black,green
actbutton=black,white
compactbutton=black,green
checkbox=green,black
actcheckbox=black,green
entry=white,black
disentry=gray,black
label=white,black
listbox=white,black
actlistbox=black,green
sellistbox=black,green
actsellistbox=black,green
textbox=white,black
acttextbox=black,white
emptyscale=,black
fullscale=green,black
helpline=white,black
roottext=white,black
'

# --- VARIÁVEIS ---
BASE_DIR="/opt/vps-manager"
DB_FILE="$BASE_DIR/data/db.txt"
LOG_FILE="$BASE_DIR/logs/system.log"
SITES_DIR="/etc/caddy/sites"
SCRIPT_URL="https://raw.githubusercontent.com/ogerrva/manager_programas/main/manager_programas.sh"
CURRENT_VERSION="1.5.0"

# --- UTILITÁRIOS ---

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        whiptail --msgbox "❌ Erro: Execute como ROOT." 10 60
        exit 1
    fi
}

# --- FUNÇÕES DE APLICAÇÃO ---

create_app() {
    APP_NAME=$(whiptail --title "NOVA APLICAÇÃO" --inputbox "Nome da Aplicação (sem espaços):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: O app '$APP_NAME' já existe." 10 60
        return
    fi

    APP_PORT=$(whiptail --title "REDE" --inputbox "Porta interna (Ex: 3000):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_PORT" ]; then return; fi

    APP_DOMAIN=$(whiptail --title "DOMÍNIO" --inputbox "Domínio (Ex: app.site.com):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_DOMAIN" ]; then return; fi

    if ! whiptail --title "CONFIRMAR" --yesno "Criar '$APP_NAME'?\n\nPorta: $APP_PORT\nDomínio: $APP_DOMAIN" 10 60; then return; fi

    useradd -m -s /bin/bash "$APP_NAME"
    
    cat > "$SITES_DIR/$APP_NAME.caddy" <<CONFIG
$APP_DOMAIN {
    reverse_proxy localhost:$APP_PORT
}
CONFIG
    systemctl reload caddy
    echo "$APP_NAME|$APP_PORT|$APP_DOMAIN" >> "$DB_FILE"
    
    log_action "App criado: $APP_NAME"
    whiptail --msgbox "✅ App Criado com Sucesso!" 10 60
}

list_apps() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app criado." 10 60
        return
    fi
    LISTA=$(awk -F'|' '{printf "App: %-15s | Porta: %-5s | Domínio: %s\n", $1, $2, $3}' "$DB_FILE")
    whiptail --title "APPS ATIVOS" --scrolltext --msgbox "$LISTA" 20 75
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum app disponível." 10 60; return; fi

    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain ($port)")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "ACESSAR TERMINAL" --menu "Selecione o App:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "================================================="
        echo "🖥️  AMBIENTE: $CHOICE"
        echo "🔙 Digite 'exit' para voltar ao menu."
        echo "================================================="
        su - "$CHOICE"
    fi
}

remove_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nada para remover." 10 60; return; fi
    
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "REMOVER -> $domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "EXCLUIR APP" --menu "Selecione para DELETAR:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --title "PERIGO" --yesno "⚠️  Apagar '$CHOICE' e todos os arquivos?" 12 60; then
            pkill -u "$CHOICE"
            userdel -r "$CHOICE"
            rm -f "$SITES_DIR/$CHOICE.caddy"
            systemctl reload caddy
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            log_action "App removido: $CHOICE"
            whiptail --msgbox "App removido." 10 60
        fi
    fi
}

# --- FUNÇÕES ADMINISTRATIVAS (NOVAS) ---

system_update() {
    if whiptail --title "ATUALIZAÇÃO" --yesno "Deseja baixar a versão mais recente do GitHub e reinstalar o painel?" 10 60; then
        clear
        echo "⬇️  Baixando atualização..."
        curl -sL "$SCRIPT_URL" > /usr/local/bin/vps-manager
        chmod +x /usr/local/bin/vps-manager
        echo "✅ Atualizado! Reiniciando..."
        sleep 1
        exec /usr/local/bin/vps-manager
    fi
}

system_repair() {
    clear
    echo "🔧 Iniciando Reparo do Sistema..."
    
    echo "1. Verificando diretórios..."
    mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs" "$SITES_DIR"
    
    echo "2. Ajustando permissões..."
    chown -R root:root "$BASE_DIR"
    chmod +x /usr/local/bin/vps-manager
    
    echo "3. Reiniciando Proxy (Caddy)..."
    systemctl restart caddy
    
    echo "4. Verificando dependências..."
    if ! command -v pm2 &> /dev/null; then npm install -g pm2; fi
    
    echo "✅ Reparo concluído."
    sleep 2
}

system_uninstall() {
    if whiptail --title "DESINSTALAR" --yesno "⚠️  PERIGO: Isso removerá o VPS Manager do sistema.\n\nDeseja continuar?" 12 60; then
        if whiptail --title "DADOS" --yesno "Deseja APAGAR também as pastas dos Apps e configurações?" 10 60; then
            rm -rf "$BASE_DIR"
            rm -rf "$SITES_DIR"
            echo "🗑️  Dados removidos."
        else
            echo "ℹ️  Dados mantidos em $BASE_DIR"
        fi
        
        # Remove atalho e boot
        rm -f /usr/local/bin/vps-manager
        sed -i '/vps-manager/d' /root/.bashrc
        
        clear
        echo "✅ Sistema desinstalado. Adeus."
        exit 0
    fi
}

admin_menu() {
    while true; do
        CHOICE=$(whiptail --title "ADMINISTRAÇÃO" --menu "Ferramentas do Sistema" 20 70 10 \
        "1" "🔄 Atualizar Painel (Git Pull)" \
        "2" "🔧 Reparar Sistema / Permissões" \
        "3" "🔁 Reiniciar Serviços (Caddy/PM2)" \
        "4" "❌ Desinstalar Sistema" \
        "0" "🔙 Voltar" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) system_update ;;
            2) system_repair; whiptail --msgbox "Reparo concluído." 10 60 ;;
            3) systemctl restart caddy; whiptail --msgbox "Serviços reiniciados." 10 60 ;;
            4) system_uninstall ;;
            0) return ;;
        esac
    done
}

# --- MENU PRINCIPAL ---

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "VPS MANAGER OS v$CURRENT_VERSION" --menu "Painel de Controle" 20 65 10 \
        "1" "🚀 Criar Nova Aplicação" \
        "2" "📋 Listar Aplicações" \
        "3" "💻 Entrar no Terminal da App" \
        "4" "🗑️  Remover Aplicação" \
        "5" "⚙️  ADMINISTRAÇÃO DO SISTEMA" \
        "6" "🔒 Shell Root (Sair do Menu)" \
        "0" "🚪 Logout SSH" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then continue; fi

        case $CHOICE in
            1) create_app ;;
            2) list_apps ;;
            3) enter_app ;;
            4) remove_app ;;
            5) admin_menu ;;
            6) clear; echo "⚠️  Shell Root. Digite 'vps-manager' para voltar."; break ;;
            0) clear; exit 0 ;;
        esac
    done
}

# --- INICIALIZAÇÃO ---
check_root
mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs" "$SITES_DIR"
touch "$DB_FILE"

main_menu
