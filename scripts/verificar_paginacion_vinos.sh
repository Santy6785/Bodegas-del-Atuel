#!/usr/bin/env bash
# =====================================================================
# verificar_paginacion_vinos.sh - Verifica paginacion de GET /vinos
# Bodegas del Atuel
#
# 1. Lee API_BASE_URL (default http://localhost:8000)
# 2. Pide /vinos?page_size=100&page=1 y guarda total
# 3. Recorre todas las paginas con page_size=100 y suma los items
# 4. Verifica que la suma de items == total y que no hay cod_vino repetidos
# 5. Imprime PASS o FAIL con los numeros
# =====================================================================

set -uo pipefail

BASE="${API_BASE_URL:-http://localhost:8000}"
PAGE_SIZE=100
TMP_CODES="$(mktemp)"
trap 'rm -f "$TMP_CODES"' EXIT

fail=0

# Verificar dependencias
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "FAIL: falta la dependencia '$cmd' en el PATH"
    fail=1
  fi
done
if [ "$fail" -ne 0 ]; then
  exit 1
fi

# Primera pagina para obtener el total
resp=""
if ! resp=$(curl -sS -f "${BASE}/vinos?page_size=${PAGE_SIZE}&page=1" 2>/dev/null); then
  echo "FAIL: no se pudo conectar a ${BASE}/vinos (¿servidor levantado?)"
  exit 1
fi

total=$(echo "$resp" | jq -r '.total // 0' 2>/dev/null || echo 0)
items_count=$(echo "$resp" | jq '.items | length' 2>/dev/null || echo 0)
echo "$resp" | jq -r '.items[].cod_vino // empty' >> "$TMP_CODES"

sum_items="$items_count"

# Calcular total de paginas
if [ "$total" -gt 0 ] 2>/dev/null; then
  total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
else
  total_pages=0
fi

# Recorrer el resto de paginas (desde la 2 hasta total_pages)
page=2
while [ "$page" -le "$total_pages" ]; do
  if ! resp=$(curl -sS -f "${BASE}/vinos?page_size=${PAGE_SIZE}&page=${page}" 2>/dev/null); then
    echo "FAIL: error en la pagina ${page} (${BASE}/vinos?page_size=${PAGE_SIZE}&page=${page})"
    fail=1
    break
  fi
  items_count=$(echo "$resp" | jq '.items | length' 2>/dev/null || echo 0)
  echo "$resp" | jq -r '.items[].cod_vino // empty' >> "$TMP_CODES"
  sum_items=$((sum_items + items_count))
  page=$((page + 1))
done

# Verificaciones
if [ "$sum_items" -eq "$total" ]; then
  echo "PASS: suma de items == total ($sum_items == $total)"
else
  echo "FAIL: suma de items != total ($sum_items != $total)"
  fail=1
fi

# Duplicados de cod_vino
dup_count=$(sort "$TMP_CODES" | uniq -d | wc -l | tr -d ' ')
if [ "$dup_count" -eq 0 ]; then
  echo "PASS: no hay cod_vino repetidos (0 duplicados)"
else
  echo "FAIL: hay cod_vino repetidos ($dup_count codigos duplicados)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "Resultado: PASS (items=$sum_items, total=$total, paginas=$total_pages, duplicados=0)"
  exit 0
else
  echo "Resultado: FAIL (items=$sum_items, total=$total, paginas=$total_pages, duplicados=$dup_count)"
  exit 1
fi
