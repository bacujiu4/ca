#!/bin/bash

# Проверка на root-доступ
if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: скрипт должен запускаться от root!" >&2
    exit 1
fi

# Логирование действий
LOG_FILE="/var/log/security_hardening.log"
echo "=== Начало настройки безопасности $(date) ===" > "$LOG_FILE"

# Функция для проверки успешности выполнения команд
run_cmd() {
    local cmd="$1"
    echo "Выполняется: $cmd" >> "$LOG_FILE"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        echo "✅ Успешно: $cmd"
    else
        echo "❌ Ошибка: $cmd (см. $LOG_FILE)"
        exit 1
    fi
}

# Обновление системы
echo "--- Обновление системы ---" >> "$LOG_FILE"
run_cmd "apt update && apt upgrade -y"
run_cmd "apt dist-upgrade -y"
run_cmd "apt autoremove -y"

#run_cmd "apt-get install netfilter-persistent"
#run_cmd "systemctl enable netfilter-persistent"
#run_cmd "systemctl start netfilter-persistent"

# Установка iptables и настройка правил
echo "--- Настройка iptables ---" >> "$LOG_FILE"
run_cmd "apt install iptables-persistent -y"
run_cmd "systemctl start netfilter-persistent.service"
run_cmd "systemctl start netfilter-persistent.service"

# Сброс текущих правил
run_cmd "iptables -F"
run_cmd "iptables -X"

# Политики по умолчанию (DROP всё неразрешенное)
run_cmd "iptables -P INPUT DROP"
run_cmd "iptables -P FORWARD DROP"
run_cmd "iptables -P OUTPUT ACCEPT"

# Разрешить loopback-интерфейс
run_cmd "iptables -A INPUT -i lo -j ACCEPT"
run_cmd "iptables -A OUTPUT -o lo -j ACCEPT"

# Разрешить уже установленные соединения
run_cmd "iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"

# Разрешить SSH
SSH_PORT="22"
run_cmd "iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT"

# Разрешить OpenVPN 1194 udp
#run_cmd "iptables -A INPUT -p udp --dport 1194 -j ACCEPT"

# Разрешить HTTP/HTTPS (если нужно)
# run_cmd "iptables -A INPUT -p tcp --dport 80 -j ACCEPT"
# run_cmd "iptables -A INPUT -p tcp --dport 443 -j ACCEPT"

# Защита от некоторых атак
run_cmd "iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP"  # NULL-пакеты
run_cmd "iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP"  # SYN-флуд
run_cmd "iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP"  # XMAS-пакеты

# ICMP (разрешить только ping)
run_cmd "iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/second -j ACCEPT"

# Сохраняем правила iptables
run_cmd "netfilter-persistent save"

# Защита SSH
echo "--- Настройка SSH ---" >> "$LOG_FILE"
#run_cmd "sed -i 's/^#Port 22/Port $SSH_PORT/' /etc/ssh/sshd_config"
run_cmd "sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
run_cmd "sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
#run_cmd "echo 'AllowUsers $(whoami)' >> /etc/ssh/sshd_config"
run_cmd "systemctl restart sshd"

# Настройка sysctl
echo "--- Настройка sysctl ---" >> "$LOG_FILE"
cat << EOF > /etc/sysctl.d/99-security.conf
# Защита от спуфинга и DDoS
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1

# Защита от переполнения буфера
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.yama.ptrace_scope=2
kernel.perf_event_paranoid=3

# Отключение IPv6 (если не используется)
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF

run_cmd "sysctl -p /etc/sysctl.d/99-security.conf"

# Установка и настройка fail2ban
#echo "--- Установка fail2ban ---" >> "$LOG_FILE"
#run_cmd "apt install fail2ban -y"
#run_cmd "systemctl enable fail2ban"
#run_cmd "systemctl start fail2ban"

# Настройка AppArmor
#echo "--- Настройка AppArmor ---" >> "$LOG_FILE"
#run_cmd "systemctl enable apparmor"
#run_cmd "systemctl start apparmor"
#run_cmd "aa-enforce /etc/apparmor.d/*"

# Запрет входа root и настройка sudo
#echo "--- Запрет входа root ---" >> "$LOG_FILE"
#run_cmd "passwd -l root"
#run_cmd "echo 'Defaults !lecture,timestamp_timeout=5' >> /etc/sudoers"

# Настройка парольной политики
#echo "--- Настройка парольной политики ---" >> "$LOG_FILE"
#run_cmd "apt install libpam-pwquality -y"
#run_cmd "sed -i 's/^# minlen =.*/minlen = 12/' /etc/security/pwquality.conf"
#run_cmd "sed -i 's/^# dcredit =.*/dcredit = -1/' /etc/security/pwquality.conf"
#run_cmd "sed -i 's/^# ucredit =.*/ucredit = -1/' /etc/security/pwquality.conf"
#run_cmd "sed -i 's/^# lcredit =.*/lcredit = -1/' /etc/security/pwquality.conf"
#run_cmd "sed -i 's/^# ocredit =.*/ocredit = -1/' /etc/security/pwquality.conf"

# Включение автоматических обновлений
echo "--- Настройка автоматических обновлений ---" >> "$LOG_FILE"
run_cmd "apt install unattended-upgrades -y"
run_cmd "dpkg-reconfigure -f noninteractive unattended-upgrades"

# Ограничение прав пользователей
#echo "--- Ограничение прав пользователей ---" >> "$LOG_FILE"
#run_cmd "chmod 700 /home/$(whoami)"
#run_cmd "chmod 600 /home/$(whoami)/.ssh/authorized_keys"

# Установка и настройка auditd (аудит)
echo "--- Настройка auditd ---" >> "$LOG_FILE"
run_cmd "apt install auditd -y"
run_cmd "systemctl enable auditd"
run_cmd "systemctl start auditd"

# Очистка системы
echo "--- Очистка системы ---" >> "$LOG_FILE"
run_cmd "apt clean"
run_cmd "rm -rf /tmp/*"

echo "=== Настройка безопасности завершена! ===" >> "$LOG_FILE"
echo "Лог сохранён в $LOG_FILE"
echo "✅ Готово! Рекомендуется перезагрузить систему: sudo reboot"
exit 0
