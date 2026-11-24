#!/usr/bin/env bash
# Roda os Passos 2 a 5 da atividade e salva as saídas em evidencias/.
# Usado pelo GitHub Actions (.github/workflows/experimentos.yml), mas também roda em Linux/macOS/WSL/Git Bash.
set -uo pipefail
cd "$(dirname "$0")/.."
EV=evidencias
mkdir -p "$EV"
TIMEFORMAT='tempo real: %3R s'
URL=http://127.0.0.1:3000/guias

cabecalho() { echo "\$ $*"; echo; }

esperar_api() {
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "$URL" && return 0   # GET não invoca a função (só existe POST)
    sleep 1
  done
  echo "start-api não respondeu" >&2; return 1
}

parar_api() {
  kill "$API_PID" 2>/dev/null; wait "$API_PID" 2>/dev/null
  docker ps -q | xargs -r docker rm -f >/dev/null 2>&1
}

chamar() {  # $1 = corpo JSON
  echo "\$ curl -X POST $URL -H 'Content-Type: application/json' -d '$1'"
  { time curl -s -w '\nHTTP %{http_code}\n' -X POST "$URL" -H "Content-Type: application/json" -d "$1"; } 2>&1
  echo
}

# 01 versões
{ cabecalho "sam --version; docker --version; python --version"
  sam --version; docker --version; python --version; uname -a; } > "$EV/01-versoes.txt" 2>&1

# 02 build
{ cabecalho "sam build"; sam build; } > "$EV/02-build.txt" 2>&1

# 03 e 04 invocação com evento
for i in 1 2; do
  { cabecalho "time sam local invoke -e events/pedido.json   (execução $i)"
    { time sam local invoke -e events/pedido.json; } 2>&1; } > "$EV/0$((i+2))-invoke-$i.txt"
done

# 05 HTTP sem warm containers
sam local start-api > "$EV/05-http-sem-warm-servidor.log" 2>&1 & API_PID=$!
esperar_api
{ cabecalho "sam local start-api   (3 chamadas, sem --warm-containers)"
  for _ in 1 2 3; do chamar '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done; } > "$EV/05-http-sem-warm.txt"
parar_api

# 06 HTTP com LAZY
sam local start-api --warm-containers LAZY > "$EV/06-http-lazy-servidor.log" 2>&1 & API_PID=$!
esperar_api
{ cabecalho "sam local start-api --warm-containers LAZY   (3 chamadas)"
  for _ in 1 2 3; do chamar '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done; } > "$EV/06-http-lazy.txt"

# 07 timeout de 3 s (mesmo servidor LAZY)
{ cabecalho "Timeout: 3 no template.yaml   (requisição com demorar=true)"
  chamar '{"requisicaoId":"R-003","demorar":true}'; } > "$EV/07-timeout-3s.txt"
sleep 2; parar_api
cp "$EV/06-http-lazy-servidor.log" "$EV/07-timeout-3s-servidor.log"

# 08 timeout de 10 s
cp template.yaml /tmp/template.original.yaml
sed -i.bak 's/Timeout: 3/Timeout: 10/' template.yaml && rm -f template.yaml.bak
{ cabecalho "Timeout: 10 no template.yaml + sam build"; grep -n "Timeout" template.yaml; sam build; } > "$EV/08-timeout-10s-build.txt" 2>&1
sam local start-api > "$EV/08-timeout-10s-servidor.log" 2>&1 & API_PID=$!
esperar_api
{ cabecalho "Timeout: 10 no template.yaml   (mesma requisição com demorar=true)"
  chamar '{"requisicaoId":"R-003","demorar":true}'; } > "$EV/08-timeout-10s.txt"
parar_api
cp /tmp/template.original.yaml template.yaml
sam build > /dev/null 2>&1

# 09 testes
{ cabecalho "python -m pytest tests -v"; python -m pytest tests -v -p no:cacheprovider; } > "$EV/09-testes.txt" 2>&1

echo "Evidências geradas:"; ls -1 "$EV"
