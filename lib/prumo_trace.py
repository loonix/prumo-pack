#!/usr/bin/env python3
"""prumo-trace: liga cada invariante declarada em .prumo/regression-rules/ ao
teste que a prova, por uma etiqueta de texto.

Contrato (mecanico, sem julgamento):

  * uma invariante ACTIVA tem pelo menos uma etiqueta `PRUMO: <id>` fora da
    prosa (codigo, CI, scripts);
  * uma invariante REVOGADA nao tem etiqueta nenhuma: um guarda a defender uma
    regra morta bloqueia o negocio em vez de o proteger;
  * uma invariante ABERTA cita uma issue e nao tem etiqueta (se ja tem prova,
    passa a ACTIVA);
  * nenhuma etiqueta cita um id que as regras nao declaram;
  * nenhum id e declarado duas vezes;
  * um ficheiro de regras sem invariante nenhuma e erro: o verificador ficou cego.

Formato de uma invariante, numa linha de lista markdown:

    - `BIZ-03` : **ACTIVA** : texto
    - `BIZ-02` : **REVOGADA 2026-09-18 (quem)** : texto
    - `BIZ-07` : **ABERTA** (issue #3) : texto

O separador entre campos e livre; so contam o id entre crases e o estado em
negrito. Agnostico de linguagem: o que se varre e texto.

Limite declarado: a etiqueta prova que ha um teste apontado a regra, nao que o
teste passou nem que morde. Isso e trabalho do runner de testes e de mutacao.

Stdlib apenas. Sai 0 conforme, 1 violacao de contrato, 2 erro de uso.
"""

import argparse
import fnmatch
import os
import re
import sys

MARCADOR = "PRUMO:"
DIRS_IGNORADOS = {
    ".git", "target", "node_modules", ".prumo", "docs", ".claude",
    "vendor", "dist", "build", ".venv", "venv", "__pycache__", ".dart_tool",
}
EXT_PROSA = {".md", ".markdown", ".rst", ".txt", ".adoc"}
TAMANHO_MAXIMO = 5 * 1024 * 1024
RE_ISSUE = re.compile(r"\(issue\s+[^)\s]+")


def id_valido(s):
    """PREFIXO-NN com sufixo opcional de uma letra minuscula: BIZ-04b."""
    if "-" not in s:
        return False
    prefixo, resto = s.split("-", 1)
    if len(prefixo) < 3 or not all("A" <= c <= "Z" for c in prefixo):
        return False
    digitos = ""
    for c in resto:
        if c.isdigit() and c.isascii():
            digitos += c
        else:
            break
    if not digitos:
        return False
    sufixo = resto[len(digitos):]
    return sufixo == "" or (len(sufixo) == 1 and "a" <= sufixo <= "z")


class Invariante:
    def __init__(self, ident, estado, sitio):
        self.id = ident
        self.estado = estado
        self.sitio = sitio


def ler_invariantes(ficheiros, raiz, erros):
    out = []
    for caminho in ficheiros:
        rel = os.path.relpath(caminho, raiz)
        with open(caminho, encoding="utf-8", errors="replace") as fh:
            linhas = fh.read().splitlines()
        for n, linha in enumerate(linhas, 1):
            linha = linha.strip()
            if not linha.startswith("- `"):
                continue
            resto = linha[3:]
            if "`" not in resto:
                continue
            ident, resto = resto.split("`", 1)
            if not id_valido(ident):
                continue
            sitio = "%s:%d" % (rel, n)
            if "**ACTIVA" in resto:
                estado = "ACTIVA"
            elif "**REVOGADA" in resto:
                estado = "REVOGADA"
            elif "**ABERTA**" in resto:
                if not RE_ISSUE.search(resto):
                    erros.append(
                        "  %s (%s) esta ABERTA sem issue. Divida sem sitio onde ser "
                        "discutida nao e divida declarada, e esquecimento." % (ident, sitio))
                estado = "ABERTA"
            else:
                erros.append(
                    "  %s (%s) nao declara estado. Escreve `- `%s` : **ACTIVA** : ...` "
                    "ou **REVOGADA <data> (<quem>)** ou **ABERTA** (issue #N)." % (ident, sitio, ident))
                continue
            out.append(Invariante(ident, estado, sitio))
    return out


def carregar_ignorados(raiz):
    padroes = []
    caminho = os.path.join(raiz, ".prumo", "trace-ignore")
    if os.path.isfile(caminho):
        with open(caminho, encoding="utf-8") as fh:
            for linha in fh:
                linha = linha.strip()
                if linha and not linha.startswith("#"):
                    padroes.append(linha)
    return padroes


def ignorado_por_padrao(rel, padroes):
    for p in padroes:
        if p.endswith("/"):
            if rel == p[:-1] or rel.startswith(p):
                return True
        elif fnmatch.fnmatch(rel, p) or rel == p:
            return True
    return False


def binario(caminho):
    try:
        if os.path.getsize(caminho) > TAMANHO_MAXIMO:
            return True
        with open(caminho, "rb") as fh:
            return b"\0" in fh.read(8192)
    except OSError:
        return True


def ficheiros_varriveis(raiz, padroes):
    for base, dirs, nomes in os.walk(raiz):
        rel_base = os.path.relpath(base, raiz)
        rel_base = "" if rel_base == "." else rel_base + "/"
        dirs[:] = sorted(
            d for d in dirs
            if d not in DIRS_IGNORADOS and not ignorado_por_padrao(rel_base + d + "/", padroes)
        )
        for nome in sorted(nomes):
            rel = rel_base + nome
            if os.path.splitext(nome)[1].lower() in EXT_PROSA:
                continue
            if ignorado_por_padrao(rel, padroes):
                continue
            caminho = os.path.join(base, nome)
            if os.path.islink(caminho) or binario(caminho):
                continue
            yield caminho, rel


def colher_etiquetas(raiz):
    padroes = carregar_ignorados(raiz)
    mapa = {}
    varridos = 0
    for caminho, rel in ficheiros_varriveis(raiz, padroes):
        varridos += 1
        try:
            with open(caminho, encoding="utf-8", errors="replace") as fh:
                texto = fh.read()
        except OSError:
            continue
        if MARCADOR not in texto:
            continue
        for n, linha in enumerate(texto.splitlines(), 1):
            if MARCADOR not in linha:
                continue
            resto = linha.split(MARCADOR, 1)[1]
            for bruto in re.split(r"[,\s]+", resto):
                ident = bruto.strip().rstrip(".:;")
                if id_valido(ident):
                    mapa.setdefault(ident, []).append("%s:%d" % (rel, n))
    return mapa, varridos


def main(argv):
    ap = argparse.ArgumentParser(prog="prumo-trace", description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=None, help="raiz do repositorio (default: cwd)")
    ap.add_argument("--rules-dir", default=".prumo/regression-rules",
                    help="directorio das regras, relativo a raiz")
    ap.add_argument("--id-valido", metavar="ID", help="so valida um id e sai 0/1")
    args = ap.parse_args(argv)

    if args.id_valido is not None:
        return 0 if id_valido(args.id_valido) else 1

    raiz = os.path.abspath(args.root or os.getcwd())
    if not os.path.isdir(raiz):
        print("prumo-trace: raiz %s nao existe" % raiz, file=sys.stderr)
        return 2

    dir_regras = os.path.join(raiz, args.rules_dir)
    ficheiros = []
    if os.path.isdir(dir_regras):
        ficheiros = sorted(
            os.path.join(dir_regras, f) for f in os.listdir(dir_regras)
            if f.endswith(".md") and os.path.isfile(os.path.join(dir_regras, f))
        )
    if not ficheiros:
        print("prumo-trace: RECUSADO, nenhum ficheiro de regras em %s. Sem regras "
              "declaradas nao ha nada a verificar, e isso nao e OK." % args.rules_dir)
        return 1

    erros_formato = []
    declaradas = ler_invariantes(ficheiros, raiz, erros_formato)
    if not declaradas and not erros_formato:
        print("prumo-trace: RECUSADO, as regras em %s nao declaram invariante nenhuma: "
              "o formato mudou ou falta declarar, e o verificador ficou cego." % args.rules_dir)
        return 1

    usadas, varridos = colher_etiquetas(raiz)
    violacoes = []

    if erros_formato:
        violacoes.append(("invariantes mal declaradas", erros_formato))

    vistas = {}
    repetidas = []
    for inv in declaradas:
        if inv.id in vistas:
            repetidas.append("  %s declarada em %s e em %s" % (inv.id, vistas[inv.id], inv.sitio))
        else:
            vistas[inv.id] = inv.sitio
    if repetidas:
        violacoes.append(("ids declarados mais do que uma vez (duas redaccoes sao duas regras)",
                          repetidas))

    orfas = ["  %s (%s) nao tem nenhuma etiqueta `PRUMO: %s`" % (i.id, i.sitio, i.id)
             for i in declaradas if i.estado == "ACTIVA" and i.id not in usadas]
    if orfas:
        violacoes.append(("invariantes ACTIVAS sem prova (etiqueta o teste ou revoga com data e autor)",
                          orfas))

    zombies = ["  %s ainda guardada em %s" % (i.id, ", ".join(usadas[i.id]))
               for i in declaradas if i.estado == "REVOGADA" and i.id in usadas]
    if zombies:
        violacoes.append(("invariantes REVOGADAS com guarda vivo (apaga o guarda ou reactiva)",
                          zombies))

    provadas = ["  %s ja provada em %s" % (i.id, ", ".join(usadas[i.id]))
                for i in declaradas if i.estado == "ABERTA" and i.id in usadas]
    if provadas:
        violacoes.append(("invariantes ABERTAS que afinal tem prova (passa a ACTIVA e fecha a issue)",
                          provadas))

    ids = set(vistas)
    fantasmas = ["  %s citada em %s" % (k, ", ".join(v))
                 for k, v in sorted(usadas.items()) if k not in ids]
    if fantasmas:
        violacoes.append(("etiquetas a citar invariantes nao declaradas", fantasmas))

    cont = {"ACTIVA": 0, "REVOGADA": 0, "ABERTA": 0}
    for i in declaradas:
        cont[i.estado] += 1
    resumo = "%d declaradas (%d activas, %d revogadas, %d abertas), %d ids etiquetados, %d ficheiros varridos" % (
        len(declaradas), cont["ACTIVA"], cont["REVOGADA"], cont["ABERTA"], len(usadas), varridos)

    if violacoes:
        for titulo, linhas in violacoes:
            print("%s:" % titulo)
            for linha in linhas:
                print(linha)
            print()
        print("prumo-trace: FALHA, %s" % resumo)
        return 1
    print("prumo-trace: OK, %s" % resumo)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
