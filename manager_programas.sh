#!/bin/bash

# ============================================================
# VPS MANAGER OS - DARK EDITION
# ============================================================

# --- CONFIGURAÇÃO DE CORES (TEMA DARK) ---
# Isso força o whiptail a usar preto/verde/branco
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

# --- VARIÁVEIS GLOBAIS ---
BASE_DIR="/opt/vps-manager"
DB_FILE="$BASE_DIR/data/db.txt"
LOG_FILE="$BASE_DIR/logs/system.log"
SITES_DIR="/etc/caddy/sites"

# --- FUNÇÕES UTILITÁRIAS ---

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        whiptail --msgbox "❌ Erro: Você precisa ser ROOT para gerenciar o sistema." 10 60
        exit 1
    fi
}

# --- FUNÇÕES DO SISTEMA ---

create_app() {
    # Input do nome
    APP_NAME=$(whiptail --title "NOVA APLICAÇÃO" --inputbox "Digite o nome da aplicação (sem espaços):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    # Validação
    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: O app '$APP_NAME' já existe." 10 60
        return
    fi

    APP_PORT=$(whiptail --title "CONFIGURAÇÃO DE REDE" --inputbox "Qual porta interna o app vai usar? (Ex: 3000)" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_PORT" ]; then return; fi

    APP_DOMAIN=$(whiptail --title "DOMÍNIO" --inputbox "Qual o domínio? (Ex: app.site.com)" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_DOMAIN" ]; then return; fi

    if ! whiptail --title "CONFIRMAÇÃO" --yesno "Criar '$APP_NAME'?\n\nPorta: $APP_PORT\nDomínio: $APP_DOMAIN" 10 60; then return; fi

    # Criação
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
        whiptail --msgbox "Nenhum app criado ainda." 10 60
        return
    fi
    
    # Formata a lista para leitura apenas
    LISTA=$(awk -F'|' '{printf "App: %-15s | Porta: %-5s | Domínio: %s\n", $1, $2, $3}' "$DB_FILE")
    whiptail --title "LISTA DE APLICAÇÕES" --scrolltext --msgbox "$LISTA" 20 75
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app disponível para acessar." 10 60
        return
    fi

    # Monta o array para o menu de seleção
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain ($port)")
    done < "$DB_FILE"

    # Menu de Seleção (Não precisa digitar)
    CHOICE=$(whiptail --title "ACESSAR TERMINAL" --menu "Selecione o App para entrar:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

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
    if [ ! -s "$DB_FILE" ]; then 
        whiptail --msgbox "Nada para remover." 10 60
        return 
    fi
    
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "REMOVER -> $domain")
    done < "$DB_FILE"

    # Menu de Seleção para Remoção
    CHOICE=$(whiptail --title "🗑️ DELETAR APP" --menu "Selecione o App para EXCLUIR:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --title "PERIGO" --yesno "⚠️  Tem certeza que deseja apagar o app '$CHOICE'?\nIsso deletará todos os arquivos e configurações dele." 12 60; then
            
            pkill -u "$CHOICE"
            userdel -r "$CHOICE"
            rm -f "$SITES_DIR/$CHOICE.caddy"
            systemctl reload caddy
            
            # Remove linha do arquivo DB
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            
            log_action "App removido: $CHOICE"
            whiptail --msgbox "App removido." 10 60
        fi
    fi
}

# --- MENU PRINCIPAL ---

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "VPS MANAGER OS" --menu "Painel de Controle" 20 60 10 \
        "1" "Criar Nova Aplicação" \
        "2" "Listar Aplicações" \
        "3" "Entrar no Terminal da App" \
        "4" "Remover Aplicação" \
        "5" "Sair (Logout)" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then continue; fi

        case $CHOICE in
            1) create_app ;;
            2) list_apps ;;
            3) enter_app ;;
            4) remove_app ;;
            5) clear; exit 0 ;;
        esac
    done
}

# --- INICIALIZAÇÃO ---
check_root
mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs" "$SITES_DIR"
touch "$DB_FILE"

main_menu
