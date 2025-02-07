#!/bin/bash

# Anti-DDoS Layer 4 Script
# Cần chạy với quyền root

# === CẤU HÌNH ===
# Thay đổi các giá trị dưới đây theo nhu cầu của bạn
SSH_PORT=22                  # Port SSH của bạn
EXTRA_PORTS="80 443 3306 3000"   # Thêm các port cần mở, cách nhau bởi dấu cách
MAX_CONNECTIONS=20          # Số kết nối tối đa cho mỗi IP
BAN_TIME=3600               # Thời gian block IP (giây)
ADMIN_EMAIL="demoover81@email.com" # Email nhận thông báo
# ================

# Cập nhật giá trị sysctl để tăng cường bảo mật network
update_sysctl() {
    echo "=== Cấu hình Network Stack ==="

    # SYN flood protection
    echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_syn_retries = 5" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_synack_retries = 2" >> /etc/sysctl.conf

    # TCP/IP protection
    echo "net.ipv4.tcp_max_syn_backlog = 4096" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_fin_timeout = 30" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_keepalive_time = 1200" >> /etc/sysctl.conf

    # Limit connections
    echo "net.ipv4.ip_local_port_range = 32768 61000" >> /etc/sysctl.conf

    # Protect against spoofing
    echo "net.ipv4.conf.all.rp_filter = 1" >> /etc/sysctl.conf
    echo "net.ipv4.conf.default.rp_filter = 1" >> /etc/sysctl.conf

    # Ignore ICMP broadcasts
    echo "net.ipv4.icmp_echo_ignore_broadcasts = 1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses = 1" >> /etc/sysctl.conf

    # Apply changes
    sysctl -p
    echo "Network Stack đã được cấu hình!"
}

# Cấu hình iptables rules
setup_iptables() {
    echo "=== Cấu hình IPTables ==="

    # Xóa tất cả rules hiện tại
    iptables -F
    iptables -X

    # Set default chain policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Cho phép loopback và established connections
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Chặn invalid packets
    iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

    # Anti-spoofing rules
    iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP

    # === Bảo vệ chống SYN Flood ===
    # Giới hạn số lượng SYN packets
    iptables -A INPUT -p tcp --syn -m limit --limit 2/s --limit-burst 30 -j ACCEPT
    iptables -A INPUT -p tcp --syn -j DROP

    # SYN flood protection với hashlimit
    iptables -A INPUT -p tcp --syn -m hashlimit \
        --hashlimit-name synflood \
        --hashlimit-above 200/sec \
        --hashlimit-burst 3 \
        --hashlimit-mode srcip \
        --hashlimit-htable-size 32768 \
        --hashlimit-htable-expire 30000 \
        -j DROP

    # Bảo vệ TCP connection states
    iptables -A INPUT -p tcp -m state --state NEW -m limit --limit 50/second --limit-burst 50 -j ACCEPT
    iptables -A INPUT -p tcp -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp -m state --state INVALID -j DROP

    # === Bảo vệ chống UDP Flood ===
    # Giới hạn UDP packets trên mỗi port
    iptables -A INPUT -p udp -m limit --limit 50/s --limit-burst 100 -j ACCEPT

    # UDP flood protection với hashlimit
    iptables -A INPUT -p udp -m hashlimit \
        --hashlimit-name udpflood \
        --hashlimit-above 100/sec \
        --hashlimit-burst 150 \
        --hashlimit-mode srcip \
        --hashlimit-htable-size 32768 \
        --hashlimit-htable-expire 30000 \
        -j DROP

    # Block UDP flood trên các port không sử dụng
    iptables -A INPUT -p udp ! --dport 53 -m limit --limit 5/m --limit-burst 10 -j ACCEPT
    iptables -A INPUT -p udp ! --dport 53 -j DROP

    # === Bảo vệ chống ICMP Flood ===
    # Giới hạn ICMP echo-request (ping)
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 10 -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

    # ICMP flood protection với hashlimit
    iptables -A INPUT -p icmp --icmp-type echo-request -m hashlimit \
        --hashlimit-name icmpflood \
        --hashlimit-above 50/sec \
        --hashlimit-burst 20 \
        --hashlimit-mode srcip \
        --hashlimit-htable-size 32768 \
        --hashlimit-htable-expire 30000 \
        -j DROP

    # Giới hạn kích thước ICMP
    iptables -A INPUT -p icmp --icmp-type echo-request -m length --length 60:76 -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

    # Port scanning protection
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

    # Chống UDP flood
    iptables -A INPUT -p udp -m limit --limit 10/s --limit-burst 20 -j ACCEPT

    # Rate limit các connections mới
    iptables -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT

    # Mở SSH port
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

    # Mở các port bổ sung
    for port in $EXTRA_PORTS; do
        iptables -A INPUT -p tcp --dport $port -j ACCEPT
        echo "Đã mở port $port"
    done

    # Lưu rules
    if command -v iptables-save >/dev/null 2>&1; then
        # Tạo thư mục nếu chưa tồn tại
        mkdir -p /etc/iptables

        # Lưu rules
        iptables-save > /etc/iptables/rules.v4

        # Thêm script khôi phục rules khi khởi động
        cat > /etc/network/if-pre-up.d/iptables << EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules.v4
EOF
        chmod +x /etc/network/if-pre-up.d/iptables
    fi

    echo "IPTables đã được cấu hình!"
}

# Cài đặt fail2ban để chặn các IP tấn công
install_fail2ban() {
    echo "=== Cài đặt Fail2ban ==="

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y fail2ban
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release
        yum install -y fail2ban
    fi

    # Cấu hình fail2ban
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = $BAN_TIME
findtime = 600
maxretry = 5
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

    # Khởi động fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban

    echo "Fail2ban đã được cài đặt và cấu hình!"
}

# Cài đặt và cấu hình DDoS Deflate
install_ddos_deflate() {
    echo "=== Cài đặt DDoS Deflate ==="

    # Cài đặt git nếu chưa có
    if ! command -v git &> /dev/null; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            apt-get install -y git
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git
        fi
    fi

    # Gỡ cài đặt phiên bản cũ nếu tồn tại
    if [ -d "/usr/local/ddos" ]; then
        echo "Phát hiện phiên bản cũ, đang gỡ cài đặt..."
        if [ -f "/usr/local/ddos/uninstall.sh" ]; then
            cd /usr/local/ddos && ./uninstall.sh
        fi
        rm -rf /usr/local/ddos
    fi

    # Xóa thư mục cũ nếu tồn tại
    if [ -d "/usr/local/src/ddos-deflate" ]; then
        echo "Xóa thư mục cài đặt cũ..."
        rm -rf /usr/local/src/ddos-deflate
    fi

    # Clone và cài đặt DDoS Deflate
    echo "Đang tải DDoS Deflate..."
    cd /usr/local/src/
    git clone https://github.com/jgmdev/ddos-deflate.git
    cd ddos-deflate
    echo "Đang cài đặt DDoS Deflate..."
    ./install.sh

    # Tạo thư mục cấu hình nếu chưa tồn tại
    mkdir -p /usr/local/ddos

    # Cấu hình DDoS Deflate
    echo "Đang cấu hình DDoS Deflate..."
    cat > /usr/local/ddos/ddos.conf << EOF
FREQ=1
NO_OF_CONNECTIONS=$MAX_CONNECTIONS
BANNED_IP_MAIL="$ADMIN_EMAIL"
BAN_PERIOD=$BAN_TIME
EOF

    echo "DDoS Deflate đã được cài đặt và cấu hình thành công!"
}

# Cài đặt và cấu hình CSF
install_csf() {
    echo "=== Cài đặt ConfigServer Security & Firewall (CSF) ==="

    # Cài đặt các gói phụ thuộc
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y perl unzip net-tools perl-libwww-perl perl-LWP-Protocol-https perl-GDGraph
    elif command -v yum >/dev/null 2>&1; then
        yum install -y perl unzip net-tools perl-libwww-perl perl-LWP-Protocol-https perl-GDGraph
    fi

    # Tải và cài đặt CSF
    cd /usr/src
    wget https://download.configserver.com/csf.tgz
    tar -xzf csf.tgz
    cd csf
    sh install.sh

    # Kiểm tra xem CSF có hoạt động không
    if [ ! -f "/etc/csf/csf.conf" ]; then
        echo "Lỗi: Không thể cài đặt CSF!"
        return 1
    fi

    # Cấu hình CSF
    sed -i 's/^TESTING = "1"/TESTING = "0"/' /etc/csf/csf.conf
    sed -i "s/^TCP_IN = .*/TCP_IN = \"$SSH_PORT,80,443,3306,3000\"/" /etc/csf/csf.conf
    sed -i "s/^TCP_OUT = .*/TCP_OUT = \"1:65535\"/" /etc/csf/csf.conf
    sed -i "s/^UDP_IN = .*/UDP_IN = \"53,123,161,162\"/" /etc/csf/csf.conf
    sed -i "s/^UDP_OUT = .*/UDP_OUT = \"1:65535\"/" /etc/csf/csf.conf

    # Cấu hình chống DDoS
    sed -i 's/^CT_LIMIT = .*/CT_LIMIT = "150"/' /etc/csf/csf.conf
    sed -i 's/^CT_INTERVAL = .*/CT_INTERVAL = "15"/' /etc/csf/csf.conf
    sed -i 's/^PS_LIMIT = .*/PS_LIMIT = "10"/' /etc/csf/csf.conf
    sed -i 's/^SYNFLOOD = .*/SYNFLOOD = "1"/' /etc/csf/csf.conf
    sed -i 's/^PORTFLOOD = .*/PORTFLOOD = "1"/' /etc/csf/csf.conf

    # Cấu hình email thông báo
    sed -i "s/^LF_EMAIL_ALERT = .*/LF_EMAIL_ALERT = \"1\"/" /etc/csf/csf.conf
    sed -i "s/^LF_EMAIL_TO = .*/LF_EMAIL_TO = \"$ADMIN_EMAIL\"/" /etc/csf/csf.conf

    # Khởi động lại CSF
    csf -r

    echo "CSF đã được cài đặt và cấu hình thành công!"
}

echo "=== Bắt đầu cấu hình Anti-DDoS Layer 4 ==="
update_sysctl
setup_iptables
install_fail2ban
install_ddos_deflate
install_csf
echo "=== Hoàn tất cấu hình Anti-DDoS Layer 4 ==="
echo "Vui lòng kiểm tra các file log để theo dõi hoạt động:"
echo "- Fail2ban log: /var/log/fail2ban.log"
echo "- DDoS Deflate log: /var/log/ddos.log"
echo "- System log: /var/log/syslog"
