#!/bin/bash

BASE_DIR="/opt/vps-manager"
CADDY_APPS="/etc/caddy/apps"

mkdir -p "$BASE_DIR/apps"
mkdir -p "$CADDY_APPS"

function pause() {
  read -p "Pressione ENTER para continuar..."
}

function create_app() {
  read -p "Nome do app (ex: app1): " APP
  read -p "Porta interna (ex: 3001): " PORT
  read -p "Dominio (ex: app1.seudominio.com): " DOMAIN

  USER="vps_$APP"

  if id "$USER" &>/dev/null; then
    echo "❌ App já existe"
    pause
    return
  fi

  echo "▶ Criando usuário $USER"
  adduser --disabled-password --gecos "" "$USER"

  echo "▶ Instalando PM2 para $USER"
  sudo -u "$USER" bash <<EOF
npm install -g pm2
pm2 startup systemd -u $USER --hp /home/$USER >/dev/null
EOF

  mkdir -p "$BASE_DIR/apps/$APP"
  echo "APP=$APP" > "$BASE_DIR/apps/$APP/info.conf"
  echo "PORT=$PORT" > "$BASE_DIR/apps/$APP/ports.conf"

  echo "▶ Criando config do Caddy"
  cat > "$CADDY_APPS/$APP.caddy" <<EOF
$DOMAIN {
    reverse_proxy localhost:$PORT
}
EOF

  caddy reload --config /etc/caddy/Caddyfile

  echo "✅ App $APP criado com sucesso!"
  echo "Usuário: $USER"
  echo "Home: /home/$USER"
  pause
}

function list_apps() {
  echo "📦 Apps instalados:"
  ls "$BASE_DIR/apps"
  pause
}

function enter_app() {
  read -p "Nome do app: " APP
  USER="vps_$APP"

  if ! id "$USER" &>/dev/null; then
    echo "❌ App não existe"
    pause
    return
  fi

  echo "▶ Entrando no app $APP"
  su - "$USER"
}

function remove_app() {
  read -p "Nome do app para remover: " APP
  USER="vps_$APP"

  if ! id "$USER" &>/dev/null; then
    echo "❌ App não existe"
    pause
    return
  fi

  userdel -r "$USER"
  rm -rf "$BASE_DIR/apps/$APP"
  rm -f "$CADDY_APPS/$APP.caddy"
  caddy reload --config /etc/caddy/Caddyfile

  echo "🗑️ App removido"
  pause
}

while true; do
  clear
  echo "=============================="
  echo "   VPS MANAGER (mini-VPS)"
  echo "=============================="
  echo "1) Criar nova VPS (App)"
  echo "2) Listar apps"
  echo "3) Entrar no app"
  echo "4) Remover app"
  echo "5) Sair"
  echo "=============================="
  read -p "Escolha: " OP

  case $OP in
    1) create_app ;;
    2) list_apps ;;
    3) enter_app ;;
    4) remove_app ;;
    5) exit ;;
    *) echo "Opção inválida"; pause ;;
  esac
done
