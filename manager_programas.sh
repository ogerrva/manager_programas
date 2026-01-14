#!/bin/bash

# ============================================================
# VPS MANAGER OS - SMART PASSWORD EDITION (v5.0)
# ============================================================

# --- TEMA ALTO CONTRASTE ---
export NEWT_COLORS='
root=,black
window=,black
border=green,black
shadow=,black
title=green,black
button=white,gray
actbutton=black,yellow
compactbutton=white,gray
checkbox=green,black
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
fullscale=green,black
helpline=white,black
roottext=white,black
'

# --- VARIÁVEIS ---
BASE_DIR="/opt/vps-manager"
DB_FILE="$BASE_DIR/data/db.txt"
CONFIG_FILE="$BASE_DIR/data/config.env"
LOG_FILE="$BASE_DIR/logs/system.log"
SCRIPT_URL="https://raw.githubusercontent.com/ogerrva/manager_programas/main/manager_programas.sh"
CURRENT_VERSION="5.0.0"

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
    APP_NAME=$(whiptail --title "1/4 - NOME" --inputbox "Nome do Ambiente (Login SSH):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$APP_NAME" ]; then return; fi

    if id "$APP_NAME" &>/dev/null; then
        whiptail --msgbox "❌ Erro: Já existe um usuário com esse nome." 10 60
        return
    fi

    # 2. Lógica de Senha (NOVO)
    PASS_MODE=$(whiptail --title "2/4 - SENHA" --menu "Escolha o tipo de senha para '$APP_NAME':" 15 70 2 \
    "1" "Criar Senha Personalizada (Digitar agora)" \
    "2" "Usar Senha Padrão do Sistema" 3>&1 1>&2 2>&3)

    if [ -z "$PASS_MODE" ]; then return; fi

    APP_PASS=""

    if [ "$PASS_MODE" == "1" ]; then
        # Senha Manual
        APP_PASS=$(whiptail --title "SENHA MANUAL" --passwordbox "Digite a senha para este app:" 10 60 3>&1 1>&2 2>&3)
        if [ -z "$APP_PASS" ]; then return; fi
    else
        # Senha Padrão
        # Carrega config se existir
        if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

        if [ -z "$DEFAULT_SYS_PASS" ]; then
            # Se não tem senha padrão salva, pede para definir
            whiptail --msgbox "⚠️ Nenhuma senha padrão definida ainda.\n\nNa próxima tela, defina a senha que será usada automaticamente para os próximos apps (Você pode usar a mesma do Root se quiser)." 14 70
            
            DEFAULT_SYS_PASS=$(whiptail --title "DEFINIR PADRÃO" --passwordbox "Digite a Senha Padrão do Sistema:" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$DEFAULT_SYS_PASS" ]; then return; fi
            
            # Salva para o futuro
            echo "DEFAULT_SYS_PASS='$DEFAULT_SYS_PASS'" > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE" # Protege o arquivo
        fi
        APP_PASS="$DEFAULT_SYS_PASS"
    fi

    # 3. Root (Sim/Não)
    IS_ROOT="N"
    if whiptail --title "3/4 - PERMISSÃO ROOT" --yesno "Deseja que '$APP_NAME' tenha permissão ROOT (Sudo)?\n\n[YES] = Pode instalar programas globais\n[NO]  = Isolado (Mais seguro)" 12 60; then
        IS_ROOT="S"
    fi

    # 4. Porta Automática
    APP_PORT=$(get_free_port)

    # Confirmação Final
    ROOT_MSG="NÃO (Isolado)"
    if [ "$IS_ROOT" == "S" ]; then ROOT_MSG="SIM (Sudo)"; fi
    PASS_MSG="Personalizada"
    if [ "$PASS_MODE" == "2" ]; then PASS_MSG="Padrão do Sistema"; fi

    if ! whiptail --title "CONFIRMAR CRIAÇÃO" --yesno "Resumo:\n\nUsuário: $APP_NAME\nSenha: [$PASS_MSG]\nRoot: $ROOT_MSG\nPorta: $APP_PORT\n\nCriar agora?" 14 60; then return; fi

    # --- EXECUÇÃO ---
    
    useradd -m -s /bin/bash "$APP_NAME"
    echo "$APP_NAME:$APP_PASS" | chpasswd

    if [ "$IS_ROOT" == "S" ]; then
        usermod -aG sudo "$APP_NAME"
        echo "$APP_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$APP_NAME"
        chmod 0440 "/etc/sudoers.d/$APP_NAME"
    fi

    manage_firewall "allow" "$APP_PORT"

    echo "$APP_NAME|$APP_PORT" >> "$DB_FILE"
    log_action "Criado: $APP_NAME (Porta: $APP_PORT | Root: $IS_ROOT)"
    
    whiptail --msgbox "✅ SUCESSO!\n\nLogin SSH Direto:\nssh $APP_NAME@SEU_IP" 12 60
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

    CHOICE=$(whiptail --title "ACESSAR (MENU)" --menu "Escolha para conectar agora:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        clear
        echo "================================================="
        echo "🚀 CONECTADO EM: $CHOICE"
        echo "🔌 PORTA LIBERADA: $(grep "^$CHOICE|" "$DB_FILE" | cut -d'|' -f2)"
        echo "🔙 Digite 'exit' para voltar ao menu."
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

    CHOICE=$(whiptail --title "DESTRUIR" --menu "Selecione para EXCLUIR:" 20 70 10 "${APPS[@]}" 3>&1 1>&2 2>&3)

    if [ ! -z "$CHOICE" ]; then
        if whiptail --title "CONFIRMAÇÃO" --yesno "⚠️  Tem certeza?\n\nIsso apaga o usuário '$CHOICE' e fecha a porta." 12 60; then
            PORT=$(grep "^$CHOICE|" "$DB_FILE" | cut -d'|' -f2)
            pkill -u "$CHOICE"
            userdel -r "$CHOICE"
            rm -f "/etc/sudoers.d/$CHOICE"
            manage_firewall "delete" "$PORT"
            grep -v "^$CHOICE|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
            log_action "Removido: $CHOICE"
            whiptail --msgbox "Ambiente destruído." 10 60
        fi
    fi
}

# --- ADMIN ---

reset_password_config() {
    if whiptail --yesno "Deseja redefinir a Senha Padrão do sistema?" 10 60; then
        rm -f "$CONFIG_FILE"
        whiptail --msgbox "Senha padrão removida. Na próxima criação de app, você poderá definir uma nova." 10 60
    fi
}

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
        "2" "Redefinir Senha Padrão" \
        "3" "Reparar Sistema" \
        "4" "Desinstalar" \
        "0" "Voltar" 3>&1 1>&2 2>&3)
        case $CHOICE in
            1) system_update ;;
            2) reset_password_config ;;
            3) system_repair; whiptail --msgbox "OK" 10 60 ;;
            4) system_uninstall ;;
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
