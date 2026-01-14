#!/bin/bash

# ============================================================
# VPS MANAGER OS - SISTEMA COMPLETO
# ============================================================

# --- CONFIGURAÇÕES ---
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
    APP_NAME=$(whiptail --inputbox "Nome da Aplicação (sem espaços, ex: api01):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    # Verificar se usuário já existe
    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: O usuário/app '$APP_NAME' já existe." 10 60
        return
    fi

    APP_PORT=$(whiptail --inputbox "Porta interna (ex: 3000):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_PORT" ]; then return; fi

    APP_DOMAIN=$(whiptail --inputbox "Domínio (ex: app.meusite.com):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_DOMAIN" ]; then return; fi

    if ! whiptail --yesno "Criar '$APP_NAME' na porta $APP_PORT para $APP_DOMAIN?" 10 60; then return; fi

    # 1. Criar Usuário Linux Isolado
    useradd -m -s /bin/bash "$APP_NAME"
    
    # 2. Configurar Proxy Reverso (Caddy)
    cat > "$SITES_DIR/$APP_NAME.caddy" <<CONFIG
$APP_DOMAIN {
    reverse_proxy localhost:$APP_PORT
}
CONFIG
    systemctl reload caddy

    # 3. Salvar no Banco de Dados
    echo "$APP_NAME|$APP_PORT|$APP_DOMAIN" >> "$DB_FILE"
    
    log_action "App criado: $APP_NAME ($APP_DOMAIN -> :$APP_PORT)"
    
    whiptail --msgbox "✅ SUCESSO!\n\nUsuário: $APP_NAME\nHome: /home/$APP_NAME\n\nPara instalar seu app:\n1. Entre no app pelo menu\n2. Clone seu git\n3. Rode 'pm2 start ...'" 15 60
}

list_apps() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app criado ainda." 10 60
        return
    fi
    
    # Formatar lista para exibição
    LISTA=$(cat "$DB_FILE" | awk -F'|' '{print "App: " $1 " | Domínio: " $3 " | Porta: " $2}')
    whiptail --title "Apps Ativos" --msgbox "$LISTA" 20 70
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then
        whiptail --msgbox "Nenhum app disponível." 10 60
        return
    fi

    # Criar array para o menu do whiptail
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "ACESSAR TERMINAL" --menu "Escolha qual App acessar:" 20 60 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "================================================="
        echo "🚀 ACESSANDO AMBIENTE: $CHOICE"
        echo "💡 Digite 'exit' para voltar ao menu principal."
        echo "================================================="
        su - "$CHOICE"
    fi
}

remove_app() {
    if [ ! -s "$DB_FILE" ]; then return; fi
    
    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "🗑️ DELETAR APP" --menu "Escolha o app para REMOVER (Irreversível):" 20 60 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --yesno "⚠️  TEM CERTEZA? Isso apagará o usuário $CHOICE e todos os arquivos dele." 10 60; then
            
            # Matar processos e remover usuário
            pkill -u "$CHOICE"
            userdel -r "$CHOICE"
            
            # Remover config do Caddy
            rm -f "$SITES_DIR/$CHOICE.caddy"
            systemctl reload caddy
            
            # Remover do DB
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            
            log_action "App removido: $CHOICE"
            whiptail --msgbox "App removido com sucesso." 10 60
        fi
    fi
}

show_status() {
    STATUS_CADDY=$(systemctl is-active caddy)
    whiptail --msgbox "Status do Sistema:\n\nCaddy Proxy: $STATUS_CADDY\nDiretório Base: $BASE_DIR" 12 60
}

# --- MENU PRINCIPAL ---

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "VPS MANAGER OS" --menu "Painel de Controle" 20 70 10 \
        "1" "Criar Nova Aplicação" \
        "2" "Listar Aplicações" \
        "3" "Entrar no Terminal da App" \
        "4" "Remover Aplicação" \
        "5" "Status dos Serviços" \
        "6" "Shell Administrativo (Root)" \
        "0" "Sair (Logout SSH)" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then continue; fi

        case $CHOICE in
            1) create_app ;;
            2) list_apps ;;
            3) enter_app ;;
            4) remove_app ;;
            5) show_status ;;
            6) clear; echo "⚠️  Você está no Shell Root. Digite 'vps-manager' para voltar."; break ;;
            0) clear; exit 0 ;;
        esac
    done
}

# --- INICIALIZAÇÃO ---
check_root
mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs" "$SITES_DIR"
touch "$DB_FILE"

# Iniciar Menu
main_menu
