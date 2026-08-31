#!/bin/bash
set -e

echo "==> Starting Vibe-Research v1.0.1..."
echo "    Frontend: http://0.0.0.0:80"
echo "    Backend:  http://0.0.0.0:8765"
echo "    Data root: ${VRA_DATA_ROOT:-/data}"

export VRA_PYTHON="${VRA_PYTHON:-/app/.venv/bin/python}"
export VRA_DATA_ROOT="${VRA_DATA_ROOT:-/data}"

mkdir -p /data

# 启动后端 API（后台）—— Node 22 需要 --experimental-strip-types 运行 .ts 文件
cd /app
node --experimental-strip-types orchestrator/src/api.ts --port 8765 --host 0.0.0.0 &
BACKEND_PID=$!

# 等待后端就绪
echo "==> Waiting for backend to start..."
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:8765/health > /dev/null 2>&1; then
        echo "==> Backend is ready!"
        break
    fi
    if ! kill -0 $BACKEND_PID 2>/dev/null; then
        echo "==> Backend process died, exiting..."
        exit 1
    fi
    if [ $i -eq 30 ]; then
        echo "==> Backend failed to start, exiting..."
        kill $BACKEND_PID 2>/dev/null
        exit 1
    fi
    sleep 1
done

# nginx 前台运行
echo "==> Starting nginx..."
exec nginx -g 'daemon off;'
