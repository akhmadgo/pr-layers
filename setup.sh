#!/bin/bash
set -e

cd "$(dirname "$0")/api"

echo "Installing dependencies..."
python3 -m venv .venv
source .venv/bin/activate
pip install -q -r requirements.txt

if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "  → Add your ANTHROPIC_API_KEY to api/.env then re-run this script"
  exit 0
fi

API_DIR="$(pwd)"

cat > /tmp/zeroth-api.service <<EOF
[Unit]
Description=Zeroth API
After=network.target

[Service]
Type=simple
WorkingDirectory=${API_DIR}
ExecStart=${API_DIR}/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5
EnvironmentFile=${API_DIR}/.env

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/zeroth-api.service /etc/systemd/system/zeroth-api.service
sudo systemctl daemon-reload
sudo systemctl enable zeroth-api
sudo systemctl restart zeroth-api

IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_VPS_IP")
echo ""
echo "Done!"
echo "  API:       http://${IP}:8080"
echo "  Extension: load zeroth/extension/ in Chrome → developer mode → Load unpacked"
echo "  Then set the endpoint in the extension popup to: http://${IP}:8080"
