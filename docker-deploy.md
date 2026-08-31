# Vibe-Research Docker 部署指南

基于 Codex Harness 的本地金融研究工作台 Docker 部署方案。

## 快速部署

```bash
docker pull ghcr.io/your-username/vibe-research:latest

docker run -d \
  --name vibe-research \
  -p 5899:80 \
  -v vibe-data:/data \
  -e VRA_DATA_ROOT=/data \
  -e VRA_API_TOKEN=$(openssl rand -hex 32) \
  ghcr.io/your-username/vibe-research:latest
```

浏览器打开 http://localhost:5899

## 环境变量

| 变量 | 必填 | 说明 |
|------|------|------|
| `VRA_API_TOKEN` | ✅ | API 认证 token（至少 32 位）。生成：`openssl rand -hex 32` |
| `VRA_DATA_ROOT` | ✅ | 容器内数据目录，通常设为 `/data` |
| `VRA_PYTHON` | 否 | Python 路径，默认 `/app/.venv/bin/python` |

## 外网反向代理

nginx 代理时会自动：
1. 注入 `Authorization: Bearer <token>` 头（API 鉴权）
2. 替换 `Origin` 为 `http://127.0.0.1:8765`（让 API 跨站检查通过，保留鉴权）

Nginx 反代示例：
```nginx
location / {
    proxy_pass http://127.0.0.1:5899;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_buffering off;
    proxy_read_timeout 600s;
}
```

## GitHub Actions 构建

手动触发，输入标签即可构建推送至 ghcr.io 和 Docker Hub。

### 所需 Secrets

| Secret | 说明 |
|--------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token |

## 多架构

支持 `linux/amd64` + `linux/arm64`。
