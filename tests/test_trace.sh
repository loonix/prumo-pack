#!/usr/bin/env bash
# prumo-trace: os contratos portados de prumo_traceability.rs, um caso por teste
# do original, mais os casos que a versao agnostica acrescenta (varios ficheiros
# de regras, trace-ignore, separador legado).
. "$(dirname "$0")/lib.sh"

T="$PACK_ROOT/bin/prumo-trace"
F="$PACK_ROOT/tests/fixtures/trace"

echo "contratos do original"
# PRUMO: PACK-01
caso_saida "ACTIVE sem etiqueta falha" 1 "SEC-02" "$T" --root "$F/activa-sem-etiqueta"
# PRUMO: PACK-02
caso_saida "etiqueta a citar id nao declarado falha" 1 "DATA-04" "$T" --root "$F/id-nao-declarado"
# PRUMO: PACK-03
caso_saida "REVOKED com guarda vivo falha" 1 "BIZ-02 ainda guardada" "$T" --root "$F/revogada-com-etiqueta"
# PRUMO: PACK-04
caso_saida "OPEN sem issue falha" 1 "OPEN sem issue" "$T" --root "$F/aberta-sem-issue"
caso_saida "OPEN com prova falha" 1 "BIZ-07 ja provada" "$T" --root "$F/aberta-com-prova"
caso_saida "invariante sem estado falha" 1 "nao declara estado" "$T" --root "$F/sem-estado"
caso_saida "id declarado duas vezes falha (mesmo entre ficheiros)" 1 "SEC-01 declarada" "$T" --root "$F/id-duplicado"
caso_saida "regras sem invariante nenhuma falham (verificador cego)" 1 "nao declaram invariante nenhuma" "$T" --root "$F/sem-invariantes"
caso_saida "sem ficheiro de regras falha" 1 "nenhum ficheiro de regras" "$T" --root "$F/sem-regras"
caso "raiz inexistente falha" 2 "$T" --root "$F/nao-existe"

echo "caso bom"
caso_saida "repositorio conforme passa" 0 "5 declaradas" "$T" --root "$F/bom"
caso_saida "prosa, docs/ e node_modules/ nao contam como etiqueta" 0 "OK" "$T" --root "$F/bom"
caso "trace-ignore exclui caminhos declarados" 0 "$T" --root "$F/ignorado"

echo "parser de ids (portado de o_parser_de_ids_aceita_o_que_a_rr_001_usa_e_recusa_prosa)"
for bom in SEC-01 BIZ-04b TIER-03 OPS-02 DATA-01 FISC-05; do
  caso "aceita $bom" 0 "$T" --id-valido "$bom"
done
for mau in sec-01 SE-01 BIZ- BIZ-x BIZ-04bb RR-001 -01 BIZ01; do
  caso "recusa $mau" 1 "$T" --id-valido "$mau"
done

echo "compatibilidade com o formato legado (travessao e estados em portugues, gerado aqui)"
D="$(tmpdir)"
mkdir -p "$D/.prumo/regression-rules" "$D/src"
TR="$(printf '\342\200\224')"
printf -- '- `SEC-01` %s **ACTIVA** %s legado\n- `BIZ-02` %s **REVOGADA 18 Set 2026 (x)** %s morta\n' \
  "$TR" "$TR" "$TR" "$TR" >"$D/.prumo/regression-rules/RR-001-core-invariants.md"
cp "$F/activa-sem-etiqueta/src/t.sh" "$D/src/t.sh"
caso "RR legada (travessao, ACTIVA, REVOGADA) e lida" 0 "$T" --root "$D"
D="$(tmpdir)"
mkdir -p "$D/.prumo/regression-rules" "$D/src"
printf -- '- `BIZ-07` : **ABERTA** (issue #3) : legado\n' >"$D/.prumo/regression-rules/RR-001-core-invariants.md"
printf '# PRUMO: BIZ-07\n' >"$D/src/t.sh"
caso_saida "ABERTA legada conta como OPEN" 1 "BIZ-07 ja provada" "$T" --root "$D"

fim
