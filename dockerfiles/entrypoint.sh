#!/bin/sh
# Copia o banco SQLite para o volume compartilhado apenas se ainda não existir
if [ ! -f /app/data/taubinha.sqlite ]; then
    cp /app/taubinha.sqlite /app/data/taubinha.sqlite
fi
exec ./TabuaMareAPI "$PORT"
