#!/bin/bash
set -euo pipefail

# Executa apenas uma instância do TabuaMareAPI na porta 4048
API_PORT="${API_PORT:-4048}"
echo "[startup] Iniciando TabuaMareAPI na porta ${API_PORT}"
exec ./TabuaMareAPI "${API_PORT}"