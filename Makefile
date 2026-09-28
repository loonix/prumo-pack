.PHONY: test leak trace fail-closed

test:
	bash tests/run.sh

leak:
	bash checks/anti-leak.sh .

trace:
	bin/prumo-trace --root .

fail-closed:
	checks/fail-closed.sh bin lib checks
