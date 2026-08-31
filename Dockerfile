# ============================================================
# Vibe-Research v1.0 Dockerfile
# 多阶段构建：前端构建 → 最终运行镜像
# ============================================================

# ── 阶段1: 构建前端 (React + Vite) ──
FROM node:22-alpine AS frontend-builder

WORKDIR /app

# 复制 desktop 依赖并安装
COPY desktop/package.json desktop/package-lock.json* ./desktop/
WORKDIR /app/desktop
RUN npm install --legacy-peer-deps

# 复制 desktop 源码 + orchestrator 源码（vite-token.ts 需要 orchestrator 类型）
COPY desktop/ ./
COPY orchestrator/src/data_root.ts ../orchestrator/src/data_root.ts

# 构建前端（跳过 TypeScript 类型检查，只做 vite build）
RUN npx vite build

# ── 阶段2: 最终运行镜像 ──
FROM node:22-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    python3 \
    python3-venv \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

WORKDIR /app

# Node.js 依赖
COPY orchestrator/package.json orchestrator/package-lock.json* ./orchestrator/
WORKDIR /app/orchestrator
RUN npm install
WORKDIR /app

# Python venv
RUN python3 -m venv /app/.venv
COPY .agents/skills/data-access/scripts/requirements.txt /tmp/requirements.txt
RUN /app/.venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# 项目代码
COPY . .

# 前端构建产物
COPY --from=frontend-builder /app/desktop/dist /usr/share/nginx/html

# 配置文件
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# 初始化（Node 22 需要 --experimental-strip-types 运行 .ts 文件）
RUN node --experimental-strip-types orchestrator/src/init.ts --python /app/.venv/bin/python 2>/dev/null || true

RUN mkdir -p /data
ENV VRA_DATA_ROOT=/data
ENV VRA_PYTHON=/app/.venv/bin/python

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost/api/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
