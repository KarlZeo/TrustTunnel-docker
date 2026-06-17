# syntax=docker/dockerfile:1
# ==========================================
# 阶段 1: Rust 编译构建阶段
# ==========================================
FROM alpine:latest AS builder

ENV TRUSTTUNNEL_VERSION=v1.0.33

RUN apk add --no-cache \
    git \
    cargo \
    rust \
    openssl-dev \
    pkgconfig \
    build-base \
    cmake \
    make \
    clang-dev \
    llvm-dev

WORKDIR /src
RUN git clone --branch ${TRUSTTUNNEL_VERSION} --depth 1 https://github.com/TrustTunnel/TrustTunnel.git .

# 将复制的目标文件名修改为实际生成的 trusttunnel_endpoint
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/src/target \
    cargo build --release && \
    cp target/release/trusttunnel_endpoint /trusttunnel_binary

# ==========================================
# 阶段 2: 最终精简运行镜像
# ==========================================
FROM alpine:latest

RUN apk add --no-cache \
    ca-certificates \
    openssl \
    bash \
    libgcc

WORKDIR /app

# 保持容器内的二进制目标名称为 trusttunnel，这样 entrypoint.sh 脚本不需要变动
COPY --from=builder /trusttunnel_binary /app/trusttunnel
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 8443
VOLUME ["/app/certs"]

ENTRYPOINT ["/app/entrypoint.sh"]