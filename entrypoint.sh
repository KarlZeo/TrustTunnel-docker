#!/bin/bash
set -e

CERT_DIR="/app/certs"
# 默认使用通用名称，避免脚本内硬编码真实证书文件名
KEY_FILE="$CERT_DIR/server.key"
CRT_FILE="$CERT_DIR/server.crt"

# 官方规范的 4 个配置文件路径
CONFIG_FILE="/app/vpn.toml"
CREDENTIALS_FILE="/app/credentials.toml"
HOSTS_FILE="/app/hosts.toml"
RULES_FILE="/app/rules.toml"

# 获取环境变量，并提供安全的无隐私默认值
USE_SELF_SIGNED=${USE_SELF_SIGNED:-"true"}
DOMAIN_OR_IP=${DOMAIN_OR_IP:-"vpn.placeholder.internal"}

# ==========================================
# 1. 证书处理逻辑 (根据配置决定是否自动生成)
# ==========================================
if [ "$USE_SELF_SIGNED" = "true" ]; then
    if [ ! -f "$KEY_FILE" ] || [ ! -f "$CRT_FILE" ]; then
        echo "检测到启用自签名证书配置，正在生成安全证书..."
        mkdir -p "$CERT_DIR"
        
        # 判断是 IP 还是 域名，从而应用正确的 SAN 扩展格式
        if [[ "$DOMAIN_OR_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            SUBJ_CN="/CN=$DOMAIN_OR_IP"
            ALT_NAME="subjectAltName = IP:$DOMAIN_OR_IP"
        else
            SUBJ_CN="/CN=$DOMAIN_OR_IP"
            ALT_NAME="subjectAltName = DNS:$DOMAIN_OR_IP"
        fi

        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$KEY_FILE" \
            -out "$CRT_FILE" \
            -subj "$SUBJ_CN" \
            -addext "$ALT_NAME" 2>/dev/null
            
        echo "自签名证书生成成功! 绑定目标: $DOMAIN_OR_IP"
    else
        echo "自签名证书已存在，跳过生成。"
    fi
else
    echo "配置为使用外部受信任证书。请确保证书已放置在挂载的 certs 目录中："
    echo "私钥路径需对应: $KEY_FILE"
    echo "证书链路径需对应: $CRT_FILE"
    
    if [ ! -f "$KEY_FILE" ] || [ ! -f "$CRT_FILE" ]; then
        echo "【错误】未在 $CERT_DIR 中找到指定的内置证书文件(server.key/server.crt)！"
        exit 1
    fi
fi

# ==========================================
# 2. 动态生成脱敏的 credentials.toml
# ==========================================
TUNNEL_USER=${TUNNEL_USER:-"admin_user"}
TUNNEL_PASS=${TUNNEL_PASS:-"SecurePassword123!"}

cat <<EOF > "$CREDENTIALS_FILE"
[[client]]
username = "$TUNNEL_USER"
password = "$TUNNEL_PASS"
EOF

# ==========================================
# 3. 动态生成脱敏的 hosts.toml
# ==========================================
cat <<EOF > "$HOSTS_FILE"
ping_hosts = []
speedtest_hosts = []
reverse_proxy_hosts = []

[[main_hosts]]
hostname = "$DOMAIN_OR_IP"
cert_chain_path = "$CRT_FILE"
private_key_path = "$KEY_FILE"
allowed_sni = []
EOF

# ==========================================
# 4. 动态生成官方标准的 rules.toml (默认全放行)
# ==========================================
cat <<EOF > "$RULES_FILE"
# Rules configuration for VPN endpoint connection filtering
EOF

# ==========================================
# 5. 动态生成官方标准的主配置 vpn.toml
# ==========================================
LISTEN_ADDR=${TUNNEL_LISTEN:-"0.0.0.0:443"}

cat <<EOF > "$CONFIG_FILE"
listen_address = "$LISTEN_ADDR"
credentials_file = "$CREDENTIALS_FILE"
rules_file = "$RULES_FILE"
ipv6_available = true
allow_private_network_connections = false
tls_handshake_timeout_secs = 10
client_listener_timeout_secs = 600
connection_establishment_timeout_secs = 30
tcp_connections_timeout_secs = 604800
udp_connections_timeout_secs = 300
speedtest_enable = false
speedtest_path = "/speedtest"
ping_enable = false
ping_path = "/ping"
auth_failure_status_code = 407

[forward_protocol]
[forward_protocol.direct]

[listen_protocols]
[listen_protocols.http1]
upload_buffer_size = 32768

[listen_protocols.http2]
initial_connection_window_size = 8388608
initial_stream_window_size = 131072
max_concurrent_streams = 1000
max_frame_size = 16384
header_table_size = 65536

[listen_protocols.quic]
recv_udp_payload_size = 1350
send_udp_payload_size = 1350
initial_max_data = 104857600
initial_max_stream_data_bidi_local = 1048576
initial_max_stream_data_bidi_remote = 1048576
initial_max_stream_data_uni = 1048576
initial_max_streams_bidi = 4096
initial_max_streams_uni = 4096
max_connection_window = 25165824
max_stream_window = 16777216
disable_active_migration = true
enable_early_data = true
message_queue_capacity = 4096
EOF

# ==========================================
# 6. 启动服务
# ==========================================
echo "正在启动 TrustTunnel (Rust Server)..."
exec /app/trusttunnel "$CONFIG_FILE" "$HOSTS_FILE"