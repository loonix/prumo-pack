.PHONY: test leak trace fail-closed

test:
	bash tests/run.sh

leak:
	checks/anti-leak.sh --deny-file ci/anti-leak.sha256 --exclude tests/fixtures/anti-leak --exclude tests/test_anti_leak.sh .

trace:
	bin/prumo-trace --root .

fail-closed:
	checks/fail-closed.sh bin lib checks
