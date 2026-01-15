#!/bin/bash

# ============================================================
# VPS MANAGER OS - HIGH CONTRAST DARK (v8.0)
# ============================================================

# --- TEMA DARK COM SELEÇÃO AMARELA (CORRIGIDO) ---
# root/window = Preto (Fundo Dark)
# button      = Cinza (Botão inativo)
# actbutton   = AMARELO (Botão onde você está)
export NEWT_COLORS='
root=,black
window=,black
border=white,black
shadow=,black
title=white,black
button=white,gray
actbutton=black,yellow
compactbutton=white,gray
checkbox=white,black
actcheckbox=black,yellow
entry=white,black
disentry=gray,black
label=white,black
listbox=white,black
actlistbox=black,yellow
sellistbox=black,yellow
actsellistbox=black,yellow
textbox=white,black
acttextbox=black,white
emptyscale=,black
fullscale=yellow,black
helpline=white,black
roottext=white,black
'

# --- VARIÁVEIS ---
BASE_DIR="/opt/vps-manager"
DB_FILE="$BASE_DIR/data/db.txt"
CONFIG_FILE="$BASE_DIR/data/config.env"
LOG_FILE="$BASE_DIR/logs/system.log"
SCRIPT_URL="https://raw.githubusercontent.com/ogerrva/manager_programas/main/manager_programas.sh"
CURRENT_VERSION="8.0.0"

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

# --- REDE ---

get_free_port() {
    local port=10000
    while true; do
        if ! ss -lntu | grep -q ":$port " && ! grep -q "|$port|" "$DB_FILE"; then
            echo "$port"
            return
        fi
        ((port++))
    done
}

manage_firewall() {
    local action=$1
    local port=$2
    if command -v ufw &> /dev/null; then
        if [ "$action" == "allow" ]; then
            ufw allow "$port"/tcp &> /dev/null
            ufw allow "$port"/udp &> /dev/null
        elif [ "$action" == "delete" ]; then
            ufw delete allow "$port"/tcp &> /dev/null
            ufw delete allow "$port"/udp &> /dev/null
        fi
    fi
}

# --- CORE ---

create_app() {
    # 1. Nome
    APP_NAME=$(whiptail --title "NOVA VPS" --inputbox "Nome do Ambiente:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: Já existe um usuário com esse nome." 10 60
        return
    fi

    # 2. Senha
    if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi
    APP_PASS=""
    
    if [ ! -z "$DEFAULT_SYS_PASS" ]; then
        APP_PASS="$DEFAULT_SYS_PASS"
    else
        CHOICE=$(whiptail --title "SENHA" --menu "Escolha:" 12 60 2 \
        "1" "Digitar Manualmente" \
        "2" "Definir Padrão (Salvar)" 3>&1 1>&2 2>&3)

        if [ -z "$CHOICE" ]; then return; fi

        if [ "$CHOICE" == "1" ]; then
            APP_PASS=$(whiptail --title "SENHA" --passwordbox "Digite a senha:" 10 60 3>&1 1>&2 2>&3)
        else
            APP_PASS=$(whiptail --title "PADRÃO" --passwordbox "Digite a Senha Padrão:" 10 60 3>&1 1>&2 2>&3)
            echo "DEFAULT_SYS_PASS='$APP_PASS'" > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        fi
    fi

    if [ -z "$APP_PASS" ]; then return; fi

    # 3. Root
    IS_ROOT="N"
    if whiptail --title "ROOT" --yesno "Dar permissão ROOT (Sudo)?" 10 60; then
        IS_ROOT="S"
    fi

    # 4. Porta
    APP_PORT=$(get_free_port)

    # Execução
    useradd -m -s /bin/bash "$APP_NAME"
    echo "$APP_NAME:$APP_PASS" | chpasswd

    # Copiar chaves SSH
    if [ -f /root/.ssh/authorized_keys ]; then
        mkdir -p "/home/$APP_NAME/.ssh"
        cp /root/.ssh/authorized_keys "/home/$APP_NAME/.ssh/"
        chown -R "$APP_NAME:$APP_NAME" "/home/$APP_NAME/.ssh"
        chmod 700 "/home/$APP_NAME/.ssh"
        chmod 600 "/home/$APP_NAME/.ssh/authorized_keys"
    fi

    if [ "$IS_ROOT" == "S" ]; then
        usermod -aG sudo "$APP_NAME"
        echo "$APP_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$APP_NAME"
        chmod 0440 "/etc/sudoers.d/$APP_NAME"
    fi

    manage_firewall "allow" "$APP_PORT"

    echo "$APP_NAME|$APP_PORT" >> "$DB_FILE"
    log_action "Criado: $APP_NAME"
    
    whiptail --msgbox "✅ SUCESSO!\n\nLogin: ssh $APP_NAME@SEU_IP" 12 60
}

list_apps() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum ambiente criado." 10 60; return; fi
    LISTA=$(awk -F'|' '{printf "%-15s | Porta: %s\n", $1, $2}' "$DB_FILE")
    whiptail --title "AMBIENTES ATIVOS" --scrolltext --msgbox "$LISTA" 20 70
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum ambiente disponível." 10 60; return; fi

    APPS=()
    while IFS='|' read -r name port; do
        APPS+=("$name" "Porta: $port")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "ACESSAR" --menu "Escolha:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "🚀 CONECTADO EM: $CHOICE"
        su - "$CHOICE"
    fi
}

remove_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nada para remover." 10 60; return; fi
    
    APPS=()
    while IFS='|' read -r name port; do
        APPS+=("$name" "DELETAR (Porta $port)")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "DESTRUIR" --menu "Selecione para EXCLUIR:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --title "CONFIRMAÇÃO" --yesno "⚠️  Tem certeza que deseja apagar '$CHOICE'?" 10 60; then
            
            PORT=$(grep "^$CHOICE|" "$DB_FILE" | cut -d'|' -f2)

            pkill -u "$CHOICE"
            userdel -r "$CHOICE" 2>/dev/null
            rm -f "/etc/sudoers.d/$CHOICE"
            
            manage_firewall "delete" "$PORT"

            # Remoção Forçada
            sed -i "/^$CHOICE|/d" "$DB_FILE"
            
            log_action "Removido: $CHOICE"
            whiptail --msgbox "✅ Ambiente '$CHOICE' destruído." 10 60
        fi
    fi
}

# --- ADMIN ---

system_update() {
    if whiptail --yesno "Atualizar painel?" 10 60; then
        clear
        curl -sL "$SCRIPT_URL" > /usr/local/bin/vps-manager
        chmod +x /usr/local/bin/vps-manager
        exec /usr/local/bin/vps-manager
    fi
}

system_repair() {
    clear
    echo "🔧 Limpando cache..."
    reset
    echo "🔧 Reparando..."
    mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs"
    chown -R root:root "$BASE_DIR"
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp
        ufw --force enable
    fi
    echo "✅ Feito."
    sleep 2
}

system_uninstall() {
    if whiptail --yesno "⚠️  Desinstalar TUDO?" 10 60; then
        rm -rf "$BASE_DIR"
        rm -f /usr/local/bin/vps-manager
        sed -i '/vps-manager/d' /root/.bashrc
        clear
        echo "Desinstalado."
        exit 0
    fi
}

admin_menu() {
    while true; do
        CHOICE=$(whiptail --title "ADMINISTRAÇÃO" --menu "Opções" 20 70 10 \
        "1" "Atualizar Painel" \
        "2" "Reparar Sistema" \
        "3" "Desinstalar" \
        "0" "Voltar" 3>&1 1>&2 2>&3)
        case $CHOICE in
            1) system_update ;;
            2) system_repair; whiptail --msgbox "OK" 10 60 ;;
            3) system_uninstall ;;
            0) return ;;
        esac
    done
}

# --- MENU PRINCIPAL ---

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "VPS MANAGER (v$CURRENT_VERSION)" --menu "Painel de Controle" 20 65 10 \
        "1" "➕ Criar Mini-VPS" \
        "2" "📋 Listar Ambientes" \
        "3" "💻 Entrar no Terminal" \
        "4" "🗑️  Destruir Ambiente" \
        "5" "⚙️  Admin / Configurações" \
        "6" "🔒 Shell Root" \
        "0" "🚪 Sair" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then continue; fi

        case $CHOICE in
            1) create_app ;;
            2) list_apps ;;
            3) enter_app ;;
            4) remove_app ;;
            5) admin_menu ;;
            6) clear; echo "Shell Root. Digite 'vps-manager' para voltar."; break ;;
            0) clear; exit 0 ;;
        esac
    done
}

# --- START ---
check_root
mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs"
touch "$DB_FILE"
main_menu
