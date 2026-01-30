#!/bin/bash

# ==========================================
# Автоустановщик Remnawave Node + Tuning
# ==========================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка Root прав сразу при старте
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[Ошибка] Пожалуйста, запустите скрипт от имени root (sudo).${NC}"
  exit 1
fi

# Функция отрисовки баннера
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "██████  ███████ ███    ███ ███    ██  █████  ";
    echo "██   ██ ██      ████  ████ ████   ██ ██   ██ ";
    echo "██████  █████   ██ ████ ██ ██ ██  ██ ███████ ";
    echo "██   ██ ██      ██  ██  ██ ██  ██ ██ ██   ██ ";
    echo "██   ██ ███████ ██      ██ ██   ████ ██   ██ ";
    echo -e "           NODE INSTALLER${NC}"
    echo ""
}

# --- ФУНКЦИЯ 1: УСТАНОВКА НОДЫ ---
install_node() {
    echo -e "${BLUE}=== УСТАНОВКА REMNAWAVE NODE ===${NC}"
    
    # Обновление
    echo -e "${BLUE}[1/4] Обновление системных пакетов...${NC}"
    apt-get update -q && apt-get upgrade -y -q
    apt-get install -y curl git

    # Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}[2/4] Docker не найден. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com | sh
        echo -e "${GREEN}Docker успешно установлен.${NC}"
    else
        echo -e "${GREEN}[2/4] Docker уже установлен.${NC}"
    fi

    echo ""
    echo -e "${YELLOW}--- Настройка ---${NC}"

    # Запрос данных
    while [[ -z "$SECRET_KEY" ]]; do
        echo -n "Введите SECRET_KEY (из панели Remnawave): "
        read SECRET_KEY
        if [[ -z "$SECRET_KEY" ]]; then
            echo -e "${RED}Secret Key обязателен!${NC}"
        fi
    done

    DEFAULT_PORT=2222
    echo -n "Введите порт узла (по умолчанию $DEFAULT_PORT): "
    read INPUT_PORT
    NODE_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    # Создание файлов
    echo ""
    echo -e "${BLUE}[3/4] Настройка конфигурации...${NC}"

    INSTALL_DIR="/opt/remnanode" # Используем путь из твоего примера

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    cat <<EOF > docker-compose.yml
services:
  remnawave:
    container_name: remnanode
    image: ghcr.io/remnawave/node:latest
    restart: always
    network_mode: host
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
EOF

    echo -e "${GREEN}Конфигурация сохранена в $INSTALL_DIR/docker-compose.yml${NC}"

    # Запуск
    echo -e "${BLUE}[4/4] Запуск контейнера...${NC}"
    docker compose pull
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}>>> Узел успешно запущен на порту ${NODE_PORT}!${NC}"
    else
        echo -e "${RED}>>> Ошибка при запуске контейнера.${NC}"
    fi
}

# --- ФУНКЦИЯ 2: ОПТИМИЗАЦИЯ СЕТИ ---
apply_optimizations() {
    echo -e "${BLUE}=== ПРИМЕНЕНИЕ СЕТЕВЫХ НАСТРОЕК (SYSCTL) ===${NC}"
    echo -e "${YELLOW}Применяются параметры: BBR, TCP FastOpen, Tweaks, IPv6 Disable...${NC}"
    
    # Создаем отдельный конфиг файл, чтобы не мусорить в основном sysctl.conf
    cat <<EOF > /etc/sysctl.d/99-remnawave-tuning.conf
# === 1. IPv6 (Отключен для стабильности) ===
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# === 2. IPv4 и Маршрутизация ===
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# === 3. Оптимизация TCP и BBR ===
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192

# Keepalive
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 15

# Буферы
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# === 4. Безопасность и Лимиты ===
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
fs.file-max = 2097152
vm.swappiness = 10
vm.overcommit_memory = 1
EOF

    echo -e "${BLUE}Применяем настройки...${NC}"
    sysctl --system > /dev/null
    
    echo -e "${GREEN}>>> Настройки успешно применены!${NC}"
}

# --- ГЛАВНЫЙ ЦИКЛ МЕНЮ ---
while true; do
    show_banner
    echo -e "${GREEN}Выберите действие:${NC}"
    echo "1) Установить Remnawave Node"
    echo "2) Применить сетевые настройки (BBR + Оптимизация)"
    echo "3) Выход"
    echo ""
    echo -n "Ваш выбор: "
    read choice

    case $choice in
        1)
            install_node
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        2)
            apply_optimizations
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        3)
            echo -e "${YELLOW}Выход.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            sleep 1
            ;;
    esac
done
