# shellcheck shell=bash
# Biblioteca minima de testes. Cada ficheiro tests/test_*.sh faz `. tests/lib.sh`,
# declara casos com `caso` e termina com `fim`. Um caso que nao correu nao conta
# como passado: `salta` regista-o a parte e o run.sh mostra-o.

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PACK_ROOT
PASSOU=0
FALHOU=0
SALTOU=0

# caso <nome> <exit esperado> <comando...>
caso() {
  local nome="$1" esperado="$2" saida obtido
  shift 2
  saida="$("$@" 2>&1)"
  obtido=$?
  if [ "$obtido" = "$esperado" ]; then
    PASSOU=$((PASSOU + 1))
    printf '  ok     %s\n' "$nome"
  else
    FALHOU=$((FALHOU + 1))
    printf '  FALHA  %s (esperado exit %s, obtido %s)\n' "$nome" "$esperado" "$obtido"
    printf '%s\n' "$saida" | head -30 | sed 's/^/         | /'
  fi
}

# caso_saida <nome> <exit esperado> <texto que a saida tem de conter> <comando...>
caso_saida() {
  local nome="$1" esperado="$2" padrao="$3" saida obtido
  shift 3
  saida="$("$@" 2>&1)"
  obtido=$?
  if [ "$obtido" = "$esperado" ] && printf '%s' "$saida" | grep -qF -- "$padrao"; then
    PASSOU=$((PASSOU + 1))
    printf '  ok     %s\n' "$nome"
  else
    FALHOU=$((FALHOU + 1))
    printf '  FALHA  %s (esperado exit %s com "%s", obtido exit %s)\n' "$nome" "$esperado" "$padrao" "$obtido"
    printf '%s\n' "$saida" | head -30 | sed 's/^/         | /'
  fi
}

# salta <nome> <razao>: o caso nao correu. Nao e sucesso.
salta() {
  SALTOU=$((SALTOU + 1))
  printf '  SALTA  %s (%s)\n' "$1" "$2"
}

# Directorio temporario apagado a saida do ficheiro de teste.
tmpdir() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/prumo-test.XXXXXX")"
  _TMPDIRS="${_TMPDIRS:-} $d"
  printf '%s' "$d"
}
_limpar() {
  local d
  for d in ${_TMPDIRS:-}; do rm -rf "$d"; done
}
trap _limpar EXIT

fim() {
  printf '  -> %d passaram, %d falharam, %d saltados\n' "$PASSOU" "$FALHOU" "$SALTOU"
  if [ -n "${PRUMO_TALLY:-}" ]; then
    printf '%s %s %s\n' "$PASSOU" "$FALHOU" "$SALTOU" >>"$PRUMO_TALLY"
  fi
  [ "$FALHOU" -eq 0 ]
}
