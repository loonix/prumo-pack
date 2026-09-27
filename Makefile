.PHONY: test leak trace

test:
	bash tests/run.sh

leak:
	bash checks/anti-leak.sh .

trace:
	bin/prumo-trace --root .
