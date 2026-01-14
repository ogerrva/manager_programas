#!/bin/bash

BASE_DIR="/opt/manager_programas/apps"
CADDY_APPS="/etc/caddy/apps"

mkdir -p "$BASE_DIR" "$CADDY_APPS"

pause() {
  read -p "Pressione ENTER para continuar..."
}

header() {
  clear
  echo "======================================"
  echo "      VPS MANAGER OS"
  echo "======================================"
}

create_app() {
  header
  read -p "Nome do app (ex: app1): " APP
  read -p "Porta interna (ex: 3001): " PORT
  read -p "Dominio (ex: app1.seudominio.com): " DOMAIN

  USER="vps_$APP"

  if id "$USER" &>/dev/null; then
    echo "❌ App já existe"
    pause
    return
  fi

  adduser --disabled-password --gecos "" "$USER"

  sudo -u "$USER" bash <<EOF
npm install -g pm2
pm2 startup systemd -u $USER --hp /home/$USER >/dev/null
EOF

  mkdir -p "$BASE_DIR/$APP"
  echo "APP=$APP" > "$BASE_DIR/$APP/info.conf"
  echo "PORT=$PORT" > "$BASE_DIR/$APP/port.conf"

  cat > "$CADDY_APPS/$APP.caddy" <<EOF
$DOMAIN {
    reverse_proxy localhost:$PORT
}
EOF

  caddy reload --config /etc/caddy/Caddyfile

  echo "✅ App criado com sucesso!"
  pause
}

list_apps() {
  header
  echo "Apps instalados:"
  ls "$BASE_DIR" 2>/dev/null || echo "Nenhum app"
  pause
}

enter_app() {
  header
  read -p "Nome do app: " APP
  USER="vps_$APP"

  if ! id "$USER" &>/dev/null; then
    echo "❌ App não existe"
    pause
    return
  fi

  su - "$USER"
}

remove_app() {
  header
  read -p "Nome do app para remover: " APP
  USER="vps_$APP"

  if ! id "$USER" &>/dev/null; then
    echo "❌ App não existe"
    pause
    return
  fi

  userdel -r "$USER"
  rm -rf "$BASE_DIR/$APP"
  rm -f "$CADDY_APPS/$APP.caddy"

  caddy reload --config /etc/caddy/Caddyfile

  echo "🗑️ App removido"
  pause
}

bash_shell() {
  clear
  echo "⚠️ Shell administrativo (exit para voltar)"
  bash
}

while true; do
  header
  echo "1) Criar nova mini-VPS (App)"
  echo "2) Listar apps"
  echo "3) Entrar em um app"
  echo "4) Remover app"
  echo "5) Abrir shell bash"
  echo "6) Reiniciar menu"
  echo "7) Sair (logout SSH)"
  echo "======================================"
  read -p "Escolha: " OP

  case $OP in
    1) create_app ;;
    2) list_apps ;;
    3) enter_app ;;
    4) remove_app ;;
    5) bash_shell ;;
    6) continue ;;
    7) exit ;;
    *) echo "Opção inválida"; pause ;;
  esac
done
