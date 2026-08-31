# Vibe-Research Docker 部署指南

基于 Codex Harness 的本地金融研究工作台 Docker 部署方案。

## 架构

```
┌──────────────────────────────────────────┐
│          Vibe-Research Container          │
│                                          │
│  ┌─────────┐     ┌───────────────────┐   │
│  │  nginx  │────▶│  orchestrator API │   │
│  │  :80    │     │  :8765            │   │
│  └────┬────┘     └───────────────────┘   │
│       │                                  │
│  ┌────▼────┐                             │
│  │ React   │                             │
│  │ Frontend│                             │
│  └─────────┘                             │
└──────────────────────────────────────────┘
```

- **nginx**：托管前端静态文件 + 反向代理 `/api/*` 到后端，自动注入 Bearer token
- **orchestrator**：TypeScript Node.js API，金融数据端点 + Agent 编排
- **Python venv**：数据取数脚本（eastmoney、baostock 等）

## 快速部署

### 1. Docker Compose（推荐）

```bash
# 创建项目目录
mkdir -p /docker/vibe-research-v2 && cd /docker/vibe-research-v2

# 创建 docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  vibe-research:
    image: ghcr.io/birdxs/vibe-research:latest
    container_name: vibe-research-v2
    restart: unless-stopped
    ports:
      - "5898:80"
    environment:
      - VRA_DATA_ROOT=/data
      - VRA_API_TOKEN=你的随机token至少32位
      - VRA_ALLOWED_ORIGINS=https://你的域名:端口
    volumes:
      - ./vibe-data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
EOF

# 启动
docker compose up -d

# 查看日志
docker compose logs -f
```

### 2. 纯 Docker

```bash
docker run -d \
  --name vibe-research-v2 \
  -p 5898:80 \
  -v /docker/vibe-research-v2/vibe-data:/data \
  -e VRA_DATA_ROOT=/data \
  -e VRA_API_TOKEN=你的随机token \
  -e VRA_ALLOWED_ORIGINS=https://你的域名:端口 \
  ghcr.io/birdxs/vibe-research:latest
```

## 环境变量

| 变量 | 必填 | 说明 |
|------|------|------|
| `VRA_API_TOKEN` | ✅ 是 | API 认证 token（至少 32 位随机字符串）。生成：`openssl rand -hex 32` |
| `VRA_DATA_ROOT` | ✅ 是 | 容器内数据目录，通常设为 `/data` 并挂载宿主机目录 |
| `VRA_ALLOWED_ORIGINS` | ✅ 是 | 允许的前端域名（逗号分隔），解决 `forbidden_origin` 错误 |
| `VRA_PYTHON` | 否 | Python 路径，默认 `/app/.venv/bin/python` |

### 生成 API Token

```bash
openssl rand -hex 32
# 输出类似：fdf2c8356f52b9be8561bfe601a50e38...
```

## 反向代理配置

### Nginx 反向代理

```nginx
server {
    listen 443 ssl;
    server_name vibe-research-v2.yourdomain.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:5898;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE 流式响应
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
```

### Caddy 反向代理

```
vibe-research-v2.yourdomain.com {
    reverse_proxy localhost:5898
}
```

## 常见问题

### 1. `forbidden_origin` 错误

**原因：** 浏览器发送的 Origin 头不在 API 的白名单中。

**解决：** 在 `VRA_ALLOWED_ORIGINS` 环境变量中添加你的域名：

```yaml
environment:
  - VRA_ALLOWED_ORIGINS=https://vibe-research-v2.birdxs.fun:89
```

多个域名用逗号分隔。

### 2. `unauthorized` 错误

**原因：** 前端请求没有携带 Bearer token。

**解决：** 确保 `VRA_API_TOKEN` 已设置，nginx 会自动注入到代理请求中。

### 3. 容器反复重启

**检查日志：**
```bash
docker compose logs -f
```

常见原因：
- `VRA_API_TOKEN` 未设置（非回环绑定必须设置）
- 端口被占用
- Python 依赖缺失

### 4. 前端页面空白但后端正常

```bash
# 检查后端健康
docker exec vibe-research-v2 curl -sf http://localhost/api/health

# 检查 nginx 是否运行
docker exec vibe-research-v2 ps aux | grep nginx

# 检查前端文件
docker exec vibe-research-v2 ls /usr/share/nginx/html/
```

### 5. 数据持久化

用户数据存储在 `/data` 目录（容器内），挂载到宿主机的 `./vibe-data`：

```bash
# 备份
tar czf vibe-data-backup.tar.gz ./vibe-data/

# 恢复
tar xzf vibe-data-backup.tar.gz
```

## GitHub Actions 构建

工作流在 `build-docker-v2` 分支，手动触发：

1. 进入 GitHub 仓库 → **Actions** → **Build & Push Docker Image**
2. 点击 **Run workflow**，输入标签（如 `v1.0.1`）
3. 构建完成后镜像推送到 ghcr.io 和 Docker Hub

### 需要的 Secrets

| Secret | 说明 |
|--------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token |

## 多架构支持

默认构建 `linux/amd64` + `linux/arm64`，支持：
- Intel/AMD 服务器
- Apple Silicon Mac
- 树莓派等 ARM 设备
