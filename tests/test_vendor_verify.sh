#!/usr/bin/env bash
# bin/prumo-vendor-verify: every file under a vendored .prumo/vendor/ matches
# the sha256 and the executable bit its MANIFEST records, nothing is missing and
# nothing unlisted sits beside them. Every case builds its vendor directory in a
# temporary directory, by hand, so the verifier is tested apart from prumo-init.
. "$(dirname "$0")/lib.sh"

V="$PACK_ROOT/bin/prumo-vendor-verify"
COMMIT="0123456789abcdef0123456789abcdef01234567"

# sha <file>
sha() {
  python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

# manifest <vendor dir>: writes a MANIFEST that lists every file currently in
# the directory, the way prumo-init does.
manifest() {
  local d="$1" f mode
  {
    echo "# prumo-pack vendored gates. Written by prumo-init; rerun it, do not edit."
    echo "format 1"
    echo "pack_commit $COMMIT"
    echo "pack_dirty no"
    echo "pack_version 0.1.0"
    (cd "$d" && find . -type f ! -name MANIFEST | sed 's|^\./||' | LC_ALL=C sort) | while read -r f; do
      if [ -x "$d/$f" ]; then mode=755; else mode=644; fi
      echo "file $(sha "$d/$f") $mode $f"
    done
  } >"$d.MANIFEST.tmp"
  mv "$d.MANIFEST.tmp" "$d/MANIFEST"
}

# vendor: a vendor directory with the verifier, two scripts and a library file,
# plus its MANIFEST.
vendor() {
  local d
  d="$(tmpdir)/vendor"
  mkdir -p "$d/bin" "$d/checks" "$d/lib"
  cp "$V" "$d/bin/prumo-vendor-verify"
  printf '#!/bin/sh\necho trace\n' >"$d/bin/prumo-trace"
  printf '#!/usr/bin/env bash\necho check\n' >"$d/checks/fail-closed.sh"
  printf 'print("lib")\n' >"$d/lib/prumo_trace.py"
  chmod 755 "$d/bin/prumo-vendor-verify" "$d/bin/prumo-trace" "$d/checks/fail-closed.sh"
  chmod 644 "$d/lib/prumo_trace.py"
  manifest "$d"
  printf '%s' "$d"
}

echo "usage"
check_output "missing vendor directory is a usage error" 2 "does not exist" "$V" "$(tmpdir)/nope"
check_output "unknown flag is a usage error" 2 "usage" "$V" --bogus
check_output "two directories is a usage error" 2 "usage" "$V" "$(vendor)" "$(vendor)"

echo "intact vendor passes"
D="$(vendor)"
check_output "intact vendor directory passes" 0 "4 file(s) match MANIFEST" "$V" "$D"
check_output "the pack commit is printed" 0 "$COMMIT" "$V" "$D"
check_output "the vendored verifier finds its own directory" 0 "OK" "$D/bin/prumo-vendor-verify"

echo "drift fails closed"
D="$(vendor)"
printf 'X' >>"$D/lib/prumo_trace.py"
check_output "one appended byte fails" 1 "lib/prumo_trace.py" "$V" "$D"
D="$(vendor)"
python3 - "$D/checks/fail-closed.sh" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, "rb").read())
b[3] ^= 1
open(p, "wb").write(bytes(b))
PY
check_output "one flipped bit fails" 1 "sha256 mismatch" "$V" "$D"
D="$(vendor)"
rm "$D/bin/prumo-trace"
check_output "missing file fails" 1 "missing" "$V" "$D"
D="$(vendor)"
printf '#!/bin/sh\nexit 0\n' >"$D/checks/extra.sh"
chmod 755 "$D/checks/extra.sh"
check_output "extra unlisted executable fails" 1 "unlisted" "$V" "$D"
D="$(vendor)"
printf 'notes\n' >"$D/NOTES.txt"
check_output "extra unlisted plain file fails" 1 "NOTES.txt" "$V" "$D"
D="$(vendor)"
mkdir -p "$D/lib/__pycache__"
printf 'x' >"$D/lib/__pycache__/prumo_trace.cpython-312.pyc"
check_output "unlisted bytecode fails (python would load it)" 1 "unlisted" "$V" "$D"
D="$(vendor)"
chmod 644 "$D/bin/prumo-trace"
check_output "executable bit dropped fails" 1 "mode" "$V" "$D"
D="$(vendor)"
chmod 755 "$D/lib/prumo_trace.py"
check_output "executable bit added fails" 1 "mode" "$V" "$D"
D="$(vendor)"
cp "$D/bin/prumo-trace" "$D/real"
rm "$D/bin/prumo-trace"
ln -s ../real "$D/bin/prumo-trace"
check_output "symlink in place of a listed file fails" 1 "not a regular file" "$V" "$D"
D="$(vendor)"
mkdir -p "$(dirname "$D")/elsewhere"
ln -s ../elsewhere "$D/linked"
check_output "unlisted symlinked directory fails" 1 "linked" "$V" "$D"

echo "MANIFEST itself fails closed"
D="$(vendor)"
rm "$D/MANIFEST"
check_output "no MANIFEST fails" 1 "MANIFEST" "$V" "$D"
D="$(vendor)"
printf 'this line means nothing\n' >>"$D/MANIFEST"
check_output "unparsable MANIFEST line fails" 1 "line" "$V" "$D"
D="$(vendor)"
grep -v '^file ' "$D/MANIFEST" >"$D/m" && mv "$D/m" "$D/MANIFEST"
rm -r "$D/bin" "$D/checks" "$D/lib"
check_output "MANIFEST listing zero files fails" 1 "no file" "$V" "$D"
D="$(vendor)"
grep -v '^pack_commit ' "$D/MANIFEST" >"$D/m" && mv "$D/m" "$D/MANIFEST"
check_output "MANIFEST without pack_commit fails" 1 "pack_commit" "$V" "$D"
D="$(vendor)"
sed "s/^pack_commit .*/pack_commit v0/" "$D/MANIFEST" >"$D/m" && mv "$D/m" "$D/MANIFEST"
check_output "a tag in place of a commit sha fails" 1 "pack_commit" "$V" "$D"
D="$(vendor)"
grep '^file .* bin/prumo-trace$' "$D/MANIFEST" >>"$D/MANIFEST"
check_output "path listed twice fails" 1 "twice" "$V" "$D"
D="$(vendor)"
printf 'file %s 644 ../outside\n' "$(sha "$D/lib/prumo_trace.py")" >>"$D/MANIFEST"
check_output "path escaping the vendor directory fails" 1 "outside" "$V" "$D"
D="$(vendor)"
printf 'file %s 644 /etc/hosts\n' "$(sha "$D/lib/prumo_trace.py")" >>"$D/MANIFEST"
check_output "absolute path fails" 1 "/etc/hosts" "$V" "$D"
D="$(vendor)"
sed 's/^format 1$/format 2/' "$D/MANIFEST" >"$D/m" && mv "$D/m" "$D/MANIFEST"
check_output "unknown MANIFEST format fails" 1 "format" "$V" "$D"
D="$(vendor)"
sed 's/^pack_dirty no$/pack_dirty yes/' "$D/MANIFEST" >"$D/m" && mv "$D/m" "$D/MANIFEST"
check_output "vendored from a dirty pack passes with a warning" 0 "WARNING" "$V" "$D"

echo "limit: the MANIFEST guards drift, not a deliberate edit"
D="$(vendor)"
printf '# edited\n' >>"$D/bin/prumo-trace"
manifest "$D"
check_output "edit plus a rewritten MANIFEST passes (branch protection is the real stop)" 0 "OK" "$V" "$D"

finish
