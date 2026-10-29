# ==========================================
# 阶段一：前端 Web 构建 (保持原样，利用了 BuildKit 缓存，非常好)
# ==========================================
FROM node:22-alpine AS node
WORKDIR /app

COPY ./app/client/web/package.json ./app/client/web/yarn.lock ./
RUN --mount=type=cache,target=/root/.yarn YARN_CACHE_FOLDER=/root/.yarn \
    yarn --frozen-lockfile

COPY ./app/client/web/ ./
RUN --mount=type=cache,target=/root/.yarn YARN_CACHE_FOLDER=/root/.yarn \
    yarn run build

# ==========================================
# 阶段二：后端 Go 编译阶段（保留所有重型构建工具）
# ==========================================
FROM golang:alpine AS go-builder

RUN apk add --no-cache build-base

WORKDIR /app/databag
RUN mkdir -p /app/databag/net

COPY ./net/server /app/databag/net/server

WORKDIR /app/databag/net/server
RUN --mount=type=cache,target=/go/pkg/mod \
    if [ -n "${DATABAG_GOARCH}" ]; then GOARCH=${DATABAG_GOARCH}; fi; \
    if [ -n "${DATABAG_GOOS}" ]; then GOOS=${DATABAG_GOOS}; fi; \
    go mod download

ARG DATABAG_GOARCH
ARG DATABAG_GOOS

RUN --mount=type=cache,target=/go/pkg/mod \
    if [ -n "${DATABAG_GOARCH}" ]; then GOARCH=${DATABAG_GOARCH}; fi; \
    if [ -n "${DATABAG_GOOS}" ]; then GOOS=${DATABAG_GOOS}; fi; \
    CGO_ENABLED=1 go build -ldflags="-s -w" -o databag .

# ==========================================
# 阶段三：生产运行环境（只装必要的运行时依赖，剔除 Go 编译器）
# ==========================================
FROM alpine:3.20

EXPOSE 7000

# 仅安装应用运行时必需的系统库和多媒体/数据库工具
RUN apk add --no-cache ca-certificates tzdata sqlite imagemagick ffmpeg curl

# 创建必要的目录结构
RUN mkdir -p /opt/databag /var/lib/databag /app/databag/net/server

# 复制 transform 工具
COPY ./net/transform /opt/databag/transform

# 从编译阶段复制编译好的 Go 二进制文件
COPY --from=go-builder /app/databag/net/server/databag /app/databag/net/server/databag

# 从前端阶段复制打包好的网页静态文件
COPY --from=node /app/dist /app/databag/net/web/build

# 复制入口脚本（假设你的代码库里有 entrypoint.sh，需要确保它被正确 COPY）
# 如果 entrypoint.sh 在 net/server 目录下：
COPY ./net/server/entrypoint.sh /app/databag/net/server/entrypoint.sh
RUN chmod +x /app/databag/net/server/entrypoint.sh

WORKDIR /app/databag/net/server

ENV DEV=0
ENV ADMIN=password

ENTRYPOINT ["/app/databag/net/server/entrypoint.sh"]
