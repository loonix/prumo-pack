#!/usr/bin/env bash
# prumo-certify: file parity, live back end and rendered DOM, checked against a
# local stand-in for the live site (tests/fixtures/certify/server.py). Every way
# the certifier could say OK without having checked anything has a case.
. "$(dirname "$0")/lib.sh"

C="$PACK_ROOT/bin/prumo-certify"
F="$PACK_ROOT/tests/fixtures/certify"
M="$F/manifests"
DOM="$PACK_ROOT/lib/prumo_certify_dom.mjs"

# Start the fixture server on a free port and stop it when the file exits.
SRV="$(tmpdir)"
python3 "$F/server.py" "$SRV/port" &
SERVER_PID=$!
trap '_cleanup; kill "$SERVER_PID" 2>/dev/null' EXIT
for _ in $(seq 100); do
  [ -s "$SRV/port" ] && break
  sleep 0.05
done
if [ ! -s "$SRV/port" ]; then
  echo "  FAIL   fixture server did not start"
  FAILED=$((FAILED + 1))
  finish
  exit 1
fi
URL="http://127.0.0.1:$(cat "$SRV/port")"
# A port that was free a moment ago: nothing listens there.
DEAD="http://127.0.0.1:$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
NO_NODE=/nonexistent/prumo-test/node

echo "file parity"
check_output "local files identical to what is served pass" 0 "3 passed, 0 failed" \
  "$C" --base-url "$URL" --manifest "$M/parity-pass.json"
check_output "a stale served file fails and is named" 1 "/index.html" \
  "$C" --base-url "$URL" --manifest "$M/parity-fail.json"
check_output "a missing local file fails" 1 "missing.html" \
  "$C" --base-url "$URL" --manifest "$M/parity-missing-local.json"
check_output "a served 404 is not parity" 1 "404" \
  "$C" --base-url "$URL/nothing-here" --manifest "$M/parity-pass.json"

echo "live back end"
check_output "requests answered as declared pass" 0 "4 passed, 0 failed" \
  "$C" --base-url "$URL" --manifest "$M/backend-pass.json"
check_output "status mismatch fails with both codes" 1 "expected 400, got 201" \
  "$C" --base-url "$URL" --manifest "$M/backend-status-mismatch.json"
check_output "an accepted write that should be refused is flagged" 1 "may have been created" \
  "$C" --base-url "$URL" --manifest "$M/backend-status-mismatch.json"
check_output "body mismatch fails" 1 "body does not contain" \
  "$C" --base-url "$URL" --manifest "$M/backend-body-mismatch.json"
check_output "secret from the environment is expanded" 0 "1 passed, 0 failed" \
  env PRUMO_TEST_API_KEY=wrong-key-on-purpose "$C" --base-url "$URL" --manifest "$M/backend-env.json"
check_output "unset environment variable fails, not sent empty" 1 "PRUMO_TEST_API_KEY is not set" \
  env -u PRUMO_TEST_API_KEY "$C" --base-url "$URL" --manifest "$M/backend-env.json"

echo "fails closed on itself"
check_output "empty manifest is refused" 1 "no checks declared" \
  "$C" --base-url "$URL" --manifest "$M/empty.json"
check_output "manifest with empty layers is refused" 1 "no checks declared" \
  "$C" --base-url "$URL" --manifest "$M/empty-lists.json"
check_output "unknown key fails (typo is not silence)" 1 "unknown key 'backnd'" \
  "$C" --base-url "$URL" --manifest "$M/unknown-key.json"
check_output "unparsable manifest fails" 1 "cannot parse" \
  "$C" --base-url "$URL" --manifest "$M/not-json.json"
check_output "missing manifest fails" 1 "no manifest" \
  "$C" --base-url "$URL" --manifest "$M/does-not-exist.json"
D="$(tmpdir)"
mkdir -p "$D/empty"
printf '{ "files": [ { "local_dir": "empty", "url_prefix": "/" } ] }\n' >"$D/m.json"
check_output "a local_dir holding zero files fails" 1 "zero files" \
  "$C" --base-url "$URL" --manifest "$D/m.json"
printf '{ "backend": [ { "name": "x", "method": "GET", "path": "/health" } ] }\n' >"$D/m.json"
check_output "backend request without expect_status fails" 1 "expect_status" \
  "$C" --base-url "$URL" --manifest "$D/m.json"
check_output "unreachable base url fails every check" 1 "0 passed, 4 failed" \
  "$C" --base-url "$DEAD" --manifest "$M/backend-pass.json"
check_output "default manifest is prumo-certify.json in the working directory" 1 "no manifest" \
  bash -c 'cd "$1" && "$2" --base-url "$3"' _ "$D" "$C" "$URL"

echo "usage errors"
check "missing --base-url is a usage error" 2 "$C" --manifest "$M/backend-pass.json"
check "base url that is not http(s) is a usage error" 2 \
  "$C" --base-url "ftp://example.com" --manifest "$M/backend-pass.json"
check "unknown option is a usage error" 2 "$C" --base-url "$URL" --bogus

echo "rendered DOM, tool missing"
check_output "frontend declared, node missing: SKIPPED counts as failure" 1 "SKIPPED" \
  env PRUMO_CERTIFY_NODE="$NO_NODE" "$C" --base-url "$URL" --manifest "$M/frontend.json"
check_output "skipped layer refuses even when the other layers pass" 1 "2 passed, 0 failed, 1 skipped" \
  env PRUMO_CERTIFY_NODE="$NO_NODE" "$C" --base-url "$URL" --manifest "$M/full.json"
check_output "no frontend declared: a missing node does not matter" 0 "4 passed, 0 failed, 0 skipped" \
  env PRUMO_CERTIFY_NODE="$NO_NODE" "$C" --base-url "$URL" --manifest "$M/backend-pass.json"

# Can playwright be loaded from a directory with no node_modules of its own?
D="$(tmpdir)"
if (cd "$D" && NODE_PATH="" node "$DOM" --probe "$M") >/dev/null 2>&1; then
  skip "frontend declared, playwright missing: SKIPPED counts as failure" \
    "playwright is resolvable from a bare directory on this machine"
else
  check_output "frontend declared, playwright missing: SKIPPED counts as failure" 1 "SKIPPED" \
    bash -c 'cd "$1" && NODE_PATH="" "$2" --base-url "$3" --manifest "$4"' _ "$D" "$C" "$URL" "$M/frontend.json"
fi

echo "rendered DOM, real browser"
if node "$DOM" --probe "$M" >/dev/null 2>&1; then
  check_output "visible text present and no console errors passes" 0 "1 passed, 0 failed" \
    "$C" --base-url "$URL" --manifest "$M/frontend.json"
  check_output "text hidden by CSS is not visible text" 1 "Hidden launch promo" \
    "$C" --base-url "$URL" --manifest "$M/frontend-hidden.json"
  check_output "a console error fails the page" 1 "console error: example failure on load" \
    "$C" --base-url "$URL" --manifest "$M/frontend-console-error.json"
else
  for n in "visible text passes" "hidden text fails" "console error fails"; do
    skip "$n" "node with playwright and chromium not available (set NODE_PATH)"
  done
fi

finish
