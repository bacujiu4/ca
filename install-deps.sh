#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "ОШИБКА: Требуются права root!"
    echo "Пожалуйста, запустите скрипт с помощью sudo: sudo $0"
    exit 1
fi

echo "Обновление пакетов..."
if ! apt-get update -qq; then
    echo "Ошибка при обновлении списка пакетов"
    exit 1
fi

# Установка зависимостей
DEPS=(
	easy-rsa
	dh-make
	devscripts
	build-essential
	prometheus-node-exporter
)

echo "Установка пакетов: ${DEPS[*]}"
if ! apt-get install -y "${DEPS[@]}"; then
    echo "Ошибка при установке пакетов"
    exit 1
fi

iptables-save > /etc/iptables/rules.v4.save

if ! iptables -C INPUT -p tcp --dport 9100 -j ACCEPT > /dev/null 2>&1; then
     echo "iptables -A INPUT -p tcp --dport 9100 -j ACCEPT"
     iptables -A INPUT -p tcp --dport 9100 -j ACCEPT
fi

netfilter-persistent save
systemctl restart iptables.service

if ! ip route show | grep -q "10.8.0.0/24 via 10.1.2.32 dev eth0"; then
    ip route add 10.8.0.0/24 via 10.1.2.32 dev eth0
    echo "Маршрут 10.8.0.0/24 добавлен через 10.1.2.32 на eth0"
fi

echo "Все зависимости установлены успешно"
