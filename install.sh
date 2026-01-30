#!/bin/bash

# ==========================================
# Автоустановщик Remnawave Node
# Для публичного использования
# ==========================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Баннер
echo -e "${BLUE}"
echo "██████  ███████ ███    ███ ███    ██  █████  ";
echo "██   ██ ██      ████  ████ ████   ██ ██   ██ ";
echo "██████  █████   ██ ████ ██ ██ ██  ██ ███████ ";
echo "██   ██ ██      ██  ██  ██ ██  ██ ██ ██   ██ ";
echo "██   ██ ███████ ██      ██ ██   ████ ██   ██ ";
echo -e "           NODE INSTALLER (RU)${NC}"
echo ""
echo -e "${YELLOW}Добро пожаловать в автоматический установщик узла Remnawave.${NC}"
echo ""

# 1. Проверка Root прав
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[Ошибка] Пожалуйста, запустите скрипт от имени root (sudo).${NC}"
  exit 1
fi

# 2. Обновление системы
echo -e "${BLUE}[1/4] Обновление системных пакетов...${NC}"
apt-get update -q && apt-get upgrade -y -q
apt-get install -y curl git

# 3. Проверка и установка Docker
if ! command -v docker &> /dev/null; then
    echo -e "${BLUE}[2/4] Docker не найден. Устанавливаем...${NC}"
    curl -fsSL https://get.docker.com | sh
    echo -e "${GREEN}Docker успешно установлен.${NC}"
else
    echo -e "${GREEN}[2/4] Docker уже установлен.${NC}"
fi

# 4. Настройка конфигурации
echo ""
echo -e "${YELLOW}--- Настройка ---${NC}"

# Запрос Secret Key
while [[ -z "$SECRET_KEY" ]]; do
    echo -n "Введите SECRET_KEY (из панели Remnawave): "
    read SECRET_KEY
    if [[ -z "$SECRET_KEY" ]]; then
        echo -e "${RED}Secret Key обязателен!${NC}"
    fi
done

# Запрос Порта
DEFAULT_PORT=2222
echo -n "Введите порт узла (по умолчанию $DEFAULT_PORT): "
read INPUT_PORT
NODE_PORT=${INPUT_PORT:-$DEFAULT_PORT}

# 5. Создание файлов
echo ""
echo -e "${BLUE}[3/4] Настройка Remnawave Node...${NC}"

INSTALL_DIR="/opt/remnanode"

# Создаем папку
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Создаем docker-compose.yml
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

# 6. Запуск контейнера
echo -e "${BLUE}[4/4] Запуск контейнера...${NC}"
docker compose pull
docker compose up -d

# 7. Финальный статус
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!   ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e "Узел запущен на порту:   ${YELLOW}${NODE_PORT}${NC}"
    echo -e "Путь установки:          ${YELLOW}${INSTALL_DIR}${NC}"
    echo ""
    echo -e "Просмотр логов:  ${BLUE}docker logs -f remnawave-node${NC}"
    echo -e "Перезапуск:      ${BLUE}docker compose restart${NC}"
    echo -e "${GREEN}Приятного использования!${NC}"
else
    echo -e "${RED}[Ошибка] Не удалось запустить контейнер.${NC}"
fi
