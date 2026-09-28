# prumo-pack

[English](README.md) | **Português**

Os gates do Prumo empacotados para instalar em qualquer repositório (GitLab, GitHub ou outro).
Uma fonte, N consumidores, em vez de scripts copiados à mão entre projetos.

O Prumo é um paradigma de engenharia para trabalho com agentes. A regra que guia este pack:
**um gate cujo token de satisfação é produzido pelo modelo não é gate.** Tudo aqui é mecânico,
nenhum check chama um LLM, e só entra o que já foi medido a morder num projeto real.

## Estado (v0.1.0)

| Peça | Estado |
|---|---|
| `bin/prumo-trace` | Funciona, 28 testes |
| `checks/fail-closed.sh` | Em construção |
| `checks/metabolic.sh` | Por fazer |
| `bin/prumo-init` (scaffold `.prumo/`, idempotente) | Por fazer |
| `bin/prumo-certify` (paridade, back-end vivo, DOM renderizado) | Por fazer |
| Templates de CI (GitLab `include:`, GitHub reusable workflow) | Por fazer |
| Plugin Claude Code (skills e hooks) | Por fazer |

## prumo-trace

Liga cada invariante declarada em `.prumo/regression-rules/` ao teste que a prova, pela etiqueta
de texto `PRUMO: <id>`. Varre texto, por isso serve para qualquer linguagem.

Declarar uma invariante, numa linha de lista markdown:

```markdown
- `BIZ-03` : **ACTIVE** : o preço nunca é negativo
- `BIZ-02` : **REVOKED 2026-09-18 (Daniel)** : texto
- `BIZ-07` : **OPEN** (issue #3) : texto
```

`ACTIVA`, `REVOGADA` e `ABERTA` continuam a ser aceites, para repositórios já declarados em português.

Marcar o teste que a prova, em qualquer ficheiro de código ou CI:

```rust
// PRUMO: BIZ-03
#[test]
fn preco_nunca_negativo() { ... }
```

Contrato verificado:

- invariante ACTIVE tem pelo menos uma etiqueta fora da prosa;
- invariante REVOKED não tem etiqueta (um guarda a defender uma regra morta bloqueia o negócio);
- invariante OPEN cita uma issue e ainda não tem etiqueta;
- nenhuma etiqueta cita um id que as regras não declaram;
- nenhum id é declarado duas vezes;
- ficheiro de regras sem invariantes é erro (verificador cego não diz OK).

```sh
bin/prumo-trace --root /caminho/do/repo
```

Sai 0 conforme, 1 violação, 2 erro de uso.

**Limite:** a etiqueta prova que existe um teste apontado à regra, não que o teste passa nem
que morde. Isso é trabalho do runner de testes e de mutação.

## Desenvolvimento

```sh
make test     # corre tests/run.sh; zero casos corridos é falha
make trace    # corre o prumo-trace sobre este repo
```

Requer apenas `bash` e `python3` (stdlib).

## Licença

MIT, Daniel Carneiro.
