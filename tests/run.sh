#!/usr/bin/env bash
# Corre todos os tests/test_*.sh e soma os casos. Sai 0 so se nenhum falhou E
# pelo menos um caso correu: um runner que nao correu nada nao pode dizer OK.
#
# Uso: tests/run.sh [padrao]   (ex.: tests/run.sh trace)
set -u

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ" || exit 2

PRUMO_TALLY="$(mktemp "${TMPDIR:-/tmp}/prumo-tally.XXXXXX")"
export PRUMO_TALLY
trap 'rm -f "$PRUMO_TALLY"' EXIT

ficheiros_falhados=""
for t in tests/test_*"${1:-}"*.sh; do
  [ -f "$t" ] || continue
  printf '== %s\n' "$t"
  if ! bash "$t"; then
    ficheiros_falhados="$ficheiros_falhados $t"
  fi
done

passou=0
falhou=0
saltou=0
while read -r p f s; do
  passou=$((passou + p))
  falhou=$((falhou + f))
  saltou=$((saltou + s))
done <"$PRUMO_TALLY"

printf '\nTOTAL: %d passaram, %d falharam, %d saltados\n' "$passou" "$falhou" "$saltou"
if [ -n "$ficheiros_falhados" ]; then
  printf 'ficheiros com falhas:%s\n' "$ficheiros_falhados"
  exit 1
fi
if [ "$passou" -eq 0 ]; then
  echo "RECUSADO: nenhum caso correu"
  exit 1
fi
exit 0
