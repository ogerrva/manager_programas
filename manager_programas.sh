#!/bin/bash

# ============================================================
# VPS MANAGER OS - ULTIMATE EDITION (Com Gestão de Root)
# ============================================================

# --- TEMA DARK ---
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
CURRENT_VERSION="1.6.0"

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

# --- FUNÇÕES PRINCIPAIS ---

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

    # Pergunta sobre ROOT na criação (Opcional)
    IS_ROOT="N"
    if whiptail --title "PERMISSÃO ESPECIAL" --yesno "Deseja conceder permissão ROOT (Sudo) para este app?\n\n⚠️ CUIDADO: Isso quebra o isolamento de segurança." 12 60; then
        IS_ROOT="S"
    fi

    if ! whiptail --title "CONFIRMAR" --yesno "Criar '$APP_NAME'?\n\nPorta: $APP_PORT\nDomínio: $APP_DOMAIN\nRoot: $IS_ROOT" 12 60; then return; fi

    # Criação
    useradd -m -s /bin/bash "$APP_NAME"
    
    # Configurar Root se solicitado
    if [ "$IS_ROOT" == "S" ]; then
        usermod -aG sudo "$APP_NAME"
        echo "$APP_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$APP_NAME"
        chmod 0440 "/etc/sudoers.d/$APP_NAME"
        log_action "App criado com ROOT: $APP_NAME"
    else
        log_action "App criado: $APP_NAME"
    fi
    
    cat > "$SITES_DIR/$APP_NAME.caddy" <<CONFIG
$APP_DOMAIN {
    reverse_proxy localhost:$APP_PORT
}
CONFIG
    systemctl reload caddy
    echo "$APP_NAME|$APP_PORT|$APP_DOMAIN" >> "$DB_FILE"
    
    whiptail --msgbox "✅ App Criado com Sucesso!" 10 60
}

list_apps() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum app criado." 10 60; return; fi
    
    # Monta lista indicando quem é ROOT
    LISTA_FMT=""
    while IFS='|' read -r name port domain; do
        ROOT_TAG=""
        if groups "$name" | grep -q "sudo"; then ROOT_TAG="[ROOT]"; fi
        LISTA_FMT+="$name ($port) $ROOT_TAG -> $domain\n"
    done < "$DB_FILE"
    
    whiptail --title "APPS ATIVOS" --scrolltext --msgbox "$LISTA_FMT" 20 75
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum app disponível." 10 60; return; fi

    APPS=()
    while IFS='|' read -r name port domain; do
        APPS+=("$name" "$domain")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "ACESSAR TERMINAL" --menu "Selecione o App:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "================================================="
        echo "🖥️  AMBIENTE: $CHOICE"
        if groups "$CHOICE" | grep -q "sudo"; then echo "⚠️  ATENÇÃO: ESTE USUÁRIO TEM PERMISSÃO ROOT (SUDO)"; fi
        echo "🔙 Digite 'exit' para voltar ao menu."
        echo "================================================="
        su - "$CHOICE"
    fi
}

manage_permissions() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum app disponível." 10 60; return; fi

    APPS=()
    while IFS='|' read -r name port domain; do
        STATUS="Padrão"
        if groups "$name" | grep -q "sudo"; then STATUS="ROOT/SUDO"; fi
        APPS+=("$name" "Status: $STATUS")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "GERENCIAR PERMISSÕES" --menu "Selecione o App para alterar:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        # Verifica status atual
        if groups "$CHOICE" | grep -q "sudo"; then
            # Tem root, perguntar se quer tirar
            if whiptail --title "REVOGAR ROOT" --yesno "O usuário '$CHOICE' tem acesso ROOT.\nDeseja REMOVER essa permissão?" 12 60; then
                deluser "$CHOICE" sudo
                rm -f "/etc/sudoers.d/$CHOICE"
                whiptail --msgbox "✅ Permissão ROOT removida de '$CHOICE'." 10 60
                log_action "Root revogado: $CHOICE"
            fi
        else
            # Não tem root, perguntar se quer dar
            if whiptail --title "CONCEDER ROOT" --yesno "⚠️  PERIGO ⚠️\n\nDeseja dar acesso ROOT (Sudo sem senha) para '$CHOICE'?\nEle terá controle total do servidor." 12 60; then
                usermod -aG sudo "$CHOICE"
                echo "$CHOICE ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$CHOICE"
                chmod 0440 "/etc/sudoers.d/$CHOICE"
                whiptail --msgbox "✅ Permissão ROOT concedida para '$CHOICE'." 10 60
                log_action "Root concedido: $CHOICE"
            fi
        fi
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
            # Remove permissão sudo se existir
            rm -f "/etc/sudoers.d/$CHOICE"
            userdel -r "$CHOICE"
            rm -f "$SITES_DIR/$CHOICE.caddy"
            systemctl reload caddy
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            log_action "App removido: $CHOICE"
            whiptail --msgbox "App removido." 10 60
        fi
    fi
}

# --- ADMINISTRAÇÃO ---

system_update() {
    if whiptail --title "ATUALIZAÇÃO" --yesno "Baixar versão mais recente do GitHub?" 10 60; then
        clear
        echo "⬇️  Baixando..."
        curl -sL "$SCRIPT_URL" > /usr/local/bin/vps-manager
        chmod +x /usr/local/bin/vps-manager
        echo "✅ Atualizado! Reiniciando..."
        sleep 1
        exec /usr/local/bin/vps-manager
    fi
}

system_repair() {
    clear
    echo "🔧 Reparando..."
    mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs" "$SITES_DIR"
    chown -R root:root "$BASE_DIR"
    chmod +x /usr/local/bin/vps-manager
    systemctl restart caddy
    if ! command -v pm2 &> /dev/null; then npm install -g pm2; fi
    echo "✅ Feito."
    sleep 2
}

system_uninstall() {
    if whiptail --title "DESINSTALAR" --yesno "Remover VPS Manager?" 10 60; then
        if whiptail --title "DADOS" --yesno "Apagar pastas dos Apps?" 10 60; then
            rm -rf "$BASE_DIR" "$SITES_DIR"
        fi
        rm -f /usr/local/bin/vps-manager
        sed -i '/vps-manager/d' /root/.bashrc
        clear
        echo "✅ Desinstalado."
        exit 0
    fi
}

admin_menu() {
    while true; do
        CHOICE=$(whiptail --title "ADMINISTRAÇÃO" --menu "Ferramentas" 20 70 10 \
        "1" "🔄 Atualizar Painel" \
        "2" "🔧 Reparar Sistema" \
        "3" "🔁 Reiniciar Serviços" \
        "4" "❌ Desinstalar Sistema" \
        "0" "🔙 Voltar" 3>&1 1>&2 2>&3)
        case $CHOICE in
            1) system_update ;;
            2) system_repair; whiptail --msgbox "Concluído." 10 60 ;;
            3) systemctl restart caddy; whiptail --msgbox "Reiniciado." 10 60 ;;
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
        "5" "🛡️  Gerenciar Permissões (Root/Sudo)" \
        "6" "⚙️  ADMINISTRAÇÃO DO SISTEMA" \
        "7" "🔒 Shell Root (Sair do Menu)" \
        "0" "🚪 Logout SSH" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then continue; fi

        case $CHOICE in
            1) create_app ;;
            2) list_apps ;;
            3) enter_app ;;
            4) remove_app ;;
            5) manage_permissions ;;
            6) admin_menu ;;
            7) clear; echo "⚠️  Shell Root. Digite 'vps-manager' para voltar."; break ;;
            0) clear; exit 0 ;;
        esac
    done
}

# --- START ---
check_root
mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs" "$SITES_DIR"
touch "$DB_FILE"
main_menu
