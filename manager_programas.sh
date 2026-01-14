#!/bin/bash

# ============================================================
# VPS MANAGER OS - RAW INFRASTRUCTURE (v3.0)
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
SCRIPT_URL="https://raw.githubusercontent.com/ogerrva/manager_programas/main/manager_programas.sh"
CURRENT_VERSION="3.0.0"

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

# --- REDE E FIREWALL ---

get_free_port() {
    # Procura porta livre a partir da 10000 (para evitar conflitos com portas baixas)
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
    local action=$1 # allow ou delete
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

# --- CORE DO SISTEMA ---

create_app() {
    # 1. Apenas pede o nome (como criar uma VPS na DigitalOcean)
    APP_NAME=$(whiptail --title "CRIAR MINI-VPS" --inputbox "Nome do Ambiente (sem espaços):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: Já existe um ambiente com esse nome." 10 60
        return
    fi

    # 2. Aloca recursos automaticamente
    APP_PORT=$(get_free_port)

    # 3. Criação (Infraestrutura)
    useradd -m -s /bin/bash "$APP_NAME"
    
    # 4. Libera Rede (Firewall)
    manage_firewall "allow" "$APP_PORT"

    # 5. Registra
    echo "$APP_NAME|$APP_PORT" >> "$DB_FILE"
    log_action "Mini-VPS criada: $APP_NAME (Porta: $APP_PORT)"
    
    # 6. Entrega
    whiptail --msgbox "✅ AMBIENTE CRIADO!\n\nUsuário: $APP_NAME\nPorta Dedicada: $APP_PORT\n\nO firewall já foi aberto nesta porta.\nConfigure seu software para rodar em 0.0.0.0:$APP_PORT" 14 60
}

list_apps() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum ambiente criado." 10 60; return; fi
    
    # Lista simples: Nome e Porta
    LISTA=$(awk -F'|' '{printf "VPS: %-15s | Porta Externa: %s\n", $1, $2}' "$DB_FILE")
    whiptail --title "MINI-VPS ATIVAS" --scrolltext --msgbox "$LISTA" 20 70
}

enter_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum ambiente disponível." 10 60; return; fi

    APPS=()
    while IFS='|' read -r name port; do
        APPS+=("$name" "Porta: $port")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "ACESSAR TERMINAL" --menu "Escolha o ambiente para conectar:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "================================================="
        echo "🚀 CONECTADO EM: $CHOICE"
        echo "🔌 SUA PORTA LIBERADA É: $(grep "^$CHOICE|" "$DB_FILE" | cut -d'|' -f2)"
        echo "🔙 Digite 'exit' para voltar ao gerenciador."
        echo "================================================="
        su - "$CHOICE"
    fi
}

remove_app() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nada para remover." 10 60; return; fi
    
    APPS=()
    while IFS='|' read -r name port; do
        APPS+=("$name" "DELETAR (Porta $port)")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "DESTRUIR AMBIENTE" --menu "Selecione para EXCLUIR:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --title "CONFIRMAÇÃO DESTRUTIVA" --yesno "⚠️  Isso apagará o usuário '$CHOICE' e todos os arquivos dele.\n\nA porta será fechada no firewall.\nContinuar?" 12 60; then
            
            # Recupera porta para fechar firewall
            PORT=$(grep "^$CHOICE|" "$DB_FILE" | cut -d'|' -f2)

            # Destruição
            pkill -u "$CHOICE"
            userdel -r "$CHOICE"
            manage_firewall "delete" "$PORT"

            # Limpa DB
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            
            log_action "Mini-VPS destruída: $CHOICE"
            whiptail --msgbox "Ambiente destruído com sucesso." 10 60
        fi
    fi
}

manage_permissions() {
    if [ ! -s "$DB_FILE" ]; then whiptail --msgbox "Nenhum ambiente disponível." 10 60; return; fi

    APPS=()
    while IFS='|' read -r name port; do
        STATUS="Padrão"
        if groups "$name" | grep -q "sudo"; then STATUS="ROOT/SUDO"; fi
        APPS+=("$name" "$STATUS")
    done < "$DB_FILE"

    CHOICE=$(whiptail --title "PERMISSÕES (ROOT)" --menu "Selecione para alterar permissões:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if groups "$CHOICE" | grep -q "sudo"; then
            if whiptail --yesno "Remover acesso ROOT de '$CHOICE'?" 10 60; then
                deluser "$CHOICE" sudo
                rm -f "/etc/sudoers.d/$CHOICE"
                whiptail --msgbox "Acesso ROOT removido." 10 60
            fi
        else
            if whiptail --yesno "⚠️  Dar acesso ROOT total para '$CHOICE'?" 10 60; then
                usermod -aG sudo "$CHOICE"
                echo "$CHOICE ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$CHOICE"
                chmod 0440 "/etc/sudoers.d/$CHOICE"
                whiptail --msgbox "Acesso ROOT concedido." 10 60
            fi
        fi
    fi
}

# --- ADMINISTRAÇÃO ---

system_update() {
    if whiptail --yesno "Atualizar painel via GitHub?" 10 60; then
        clear
        curl -sL "$SCRIPT_URL" > /usr/local/bin/vps-manager
        chmod +x /usr/local/bin/vps-manager
        exec /usr/local/bin/vps-manager
    fi
}

system_repair() {
    clear
    echo "🔧 Reparando permissões e firewall..."
    mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs"
    chown -R root:root "$BASE_DIR"
    
    # Garante portas básicas da VPS principal
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp
        ufw --force enable
    fi
    
    echo "✅ Concluído."
    sleep 2
}

system_uninstall() {
    if whiptail --yesno "⚠️  Desinstalar o gerenciador?" 10 60; then
        if whiptail --yesno "Apagar também os dados dos usuários criados?" 10 60; then
            rm -rf "$BASE_DIR"
        fi
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
        CHOICE=$(whiptail --title "VPS MANAGER OS (RAW)" --menu "Gerenciador de Ambientes" 20 65 10 \
        "1" "➕ Criar Mini-VPS (Ambiente)" \
        "2" "📋 Listar Ambientes" \
        "3" "💻 Entrar no Terminal" \
        "4" "🗑️  Destruir Ambiente" \
        "5" "🛡️  Gerenciar Root/Sudo" \
        "6" "⚙️  Admin / Atualizar" \
        "7" "🔒 Shell Root" \
        "0" "🚪 Sair" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then continue; fi

        case $CHOICE in
            1) create_app ;;
            2) list_apps ;;
            3) enter_app ;;
            4) remove_app ;;
            5) manage_permissions ;;
            6) admin_menu ;;
            7) clear; echo "Shell Root. Digite 'vps-manager' para voltar."; break ;;
            0) clear; exit 0 ;;
        esac
    done
}

# --- START ---
check_root
mkdir -p "$BASE_DIR/data" "$BASE_DIR/logs"
touch "$DB_FILE"
main_menu
