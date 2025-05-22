#!/bin/bash

# First argument: Client identifier

# Проверка прав root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Ошибка: скрипт должен быть запущен с правами root" >&2
        exit 1
    fi
}

# Инициализация переменных
init_vars() {
    CURRENT_USER=$(logname)
    CURRENT_USER_HOME_DIR=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
    EASY_USER="easy-rsa-user"
    EASY_HOME=$(getent passwd "$EASY_USER" | cut -d: -f6)
    EASY_RSA_DIR="$EASY_HOME/easy-rsa"
    CLIENT_NAME="$1"
    CLIENT_DIR="$CURRENT_USER_HOME_DIR/openvpn-clients-configure/clients"
    
    # Создаем директорию для клиента
    mkdir -p "$CLIENT_DIR" || {
        echo "Ошибка: не удалось создать директорию '$CLIENT_DIR'" >&2
        exit 1
    }
}

# Создание базового конфига
create_base_config() {
    local base_conf_file="$EASY_HOME/base.conf"
    local base_conf_content='client
dev tun
proto udp
remote 51.250.69.99 1194
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
remote-cert-tls server
tls-crypt
cipher AES-256-GCM
auth SHA256
verb 3
key-direction 1

# For LINUX client only
;script-security 2
;up /etc/openvpn/update-resolv-conf
;down /etc/openvpn/update-resolv-conf

#for LNUX clients with system-resolved
;script-security 2
;up /etc/openvpn/update-systemd-resolved
;down /etc/openvpn/update-systemd-resolved
;down-pre
;dhcp-option DOMAIN-ROUTE'

    echo "Создание файла базовой конфигурации '$base_conf_file'..."
    echo "$base_conf_content" > "$base_conf_file" || {
        echo "Ошибка: не удалось создать файл '$base_conf_file'" >&2
        return 1
    }
}

# Генерация сертификатов
generate_certs() {
    echo "Генерация сертификатов для клиента '$CLIENT_NAME'..."
    
    sudo -u "$EASY_USER" sh -c '
        cd "'"$EASY_RSA_DIR"'" || {
            echo "Ошибка: не удалось перейти в директорию '"$EASY_RSA_DIR"'" >&2
            exit 1
        }

        echo "Генерация запроса..."
        ./easyrsa --batch --req-cn="'"$CLIENT_NAME"'" gen-req "'"$CLIENT_NAME"'" nopass || {
            echo "Ошибка при генерации запроса для клиента '"$CLIENT_NAME"'" >&2
            exit 1
        }

        echo "Подписание запроса..."
        ./easyrsa --batch sign-req client "'"$CLIENT_NAME"'" || {
            echo "Ошибка при подписании запроса для клиента '"$CLIENT_NAME"'" >&2
            exit 1
        }
    ' || return 1
}

# Создание OVPN файла
create_ovpn_file() {
    echo "Создание единого .ovpn файла для клиента $CLIENT_NAME..."
    {
        cat "$EASY_HOME/base.conf"
	echo -e "<ca>"
	cat "$EASY_RSA_DIR/pki/ca.crt"
	echo -e "</ca>\n<cert>"
	cat "$EASY_RSA_DIR/pki/issued/$CLIENT_NAME.crt"
	echo -e "</cert>\n<key>"
	cat "$EASY_RSA_DIR/pki/private/$CLIENT_NAME.key"
	echo -e "</key>"
	[ -f "$EASY_RSA_DIR/pki/ta.key" ] && {
	    echo -e "<tls-crypt>"
	    cat "$EASY_RSA_DIR/pki/ta.key"
	    echo -e "</tls-crypt>"
	}
    } > "$CLIENT_DIR/$CLIENT_NAME.ovpn" && \
	    chown -R "$CURRENT_USER:$CURRENT_USER" "$CLIENT_DIR" || \
	    {
                echo "Ошибка: не удалось создать .ovpn файл" >&2
   	        return 1
	    }
}


# Основной поток выполнения
main() {
    check_root
    init_vars "$@"
    
    if create_base_config && generate_certs; then
        echo "Успешно: сертификат для клиента $CLIENT_NAME создан и подписан"
        
        if create_ovpn_file; then
            echo "Готово! Конфигурация для клиента $CLIENT_NAME создана в $CLIENT_DIR"
            exit 0
        fi
    fi
    
    echo "Ошибка: не удалось создать конфигурацию для клиента $CLIENT_NAME" >&2
    exit 1
}

# Запуск main функции
main "$@"
