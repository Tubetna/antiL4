# Node.js Project

This is a Node.js project created with Express.js.

## Installation

```bash
npm install
```

## Running the Application

```bash
npm start
```

# Anti DDoS Layer 4 Protection

Dự án này cung cấp hai phần chính:
1. Node.js server với các biện pháp bảo vệ DDoS cơ bản
2. Script bash để cấu hình bảo vệ DDoS Layer 4 ở cấp độ hệ thống

## 1. Node.js Server

### Cài đặt

```bash
npm install
```

### Chạy ứng dụng

```bash
npm start
```

## 2. Anti DDoS Layer 4 Script

Script `anti_ddos.sh` cung cấp các biện pháp bảo vệ toàn diện cho VPS của bạn chống lại các cuộc tấn công DDoS Layer 4.

### Các tính năng

- Tối ưu hóa Network Stack
- Cấu hình IPTables với các rules chống DDoS
- Cài đặt và cấu hình Fail2ban
- Cài đặt DDoS Deflate

### Cách sử dụng

1. **Upload script lên VPS**
   ```bash
   scp anti_ddos.sh root@your_vps_ip:/root/
   ```

2. **SSH vào VPS**
   ```bash
   ssh root@your_vps_ip
   ```

3. **Cấp quyền thực thi cho script**
   ```bash
   chmod +x anti_ddos.sh
   ```

4. **Chạy script với quyền root**
   ```bash
   sudo ./anti_ddos.sh
   ```

### Monitoring

Sau khi cài đặt, bạn có thể monitor hệ thống bằng các lệnh sau:

1. **Kiểm tra IP bị block bởi Fail2ban**
   ```bash
   fail2ban-client status
   ```

2. **Xem các rules IPTables hiện tại**
   ```bash
   iptables -L -n
   ```

3. **Xem log của DDoS Deflate**
   ```bash
   cat /var/log/ddos.log
   ```

### Tùy chỉnh cấu hình

1. **IPTables**: Chỉnh sửa các port trong script `anti_ddos.sh`
   ```bash
   # Mở thêm port (ví dụ: port 8080)
   iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
   ```

2. **DDoS Deflate**: Chỉnh sửa file `/usr/local/ddos/ddos.conf`
   ```bash
   # Các thông số có thể tùy chỉnh
   FREQ=1                    # Tần suất kiểm tra (phút)
   NO_OF_CONNECTIONS=150     # Số connections tối đa/IP
   BAN_PERIOD=600           # Thời gian block (giây)
   ```

3. **Fail2ban**: Chỉnh sửa file `/etc/fail2ban/jail.local`
   ```bash
   # Các thông số có thể tùy chỉnh
   bantime = 3600           # Thời gian block (giây)
   findtime = 600           # Thời gian tìm kiếm (giây)
   maxretry = 5             # Số lần thử tối đa
   ```

### Lưu ý quan trọng

1. Backup các cấu hình hiện tại trước khi chạy script
2. Kiểm tra với nhà cung cấp VPS về chính sách DDoS
3. Đảm bảo không block các IP quan trọng
4. Theo dõi log thường xuyên để điều chỉnh cấu hình phù hợp

### Gỡ cài đặt

Nếu cần gỡ cài đặt các biện pháp bảo vệ:

1. **Gỡ Fail2ban**
   ```bash
   sudo apt-get remove fail2ban   # Ubuntu/Debian
   sudo yum remove fail2ban       # CentOS/RHEL
   ```

2. **Gỡ DDoS Deflate**
   ```bash
   cd /usr/local/ddos
   ./uninstall.sh
   ```

3. **Reset IPTables**
   ```bash
   iptables -F
   iptables -X
   iptables -P INPUT ACCEPT
   iptables -P FORWARD ACCEPT
   iptables -P OUTPUT ACCEPT
   ```
