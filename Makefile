.PHONY: help test install uninstall doctor dry lint parity

help:
	@echo "make test       run the whole suite (syntax, parity, self-tests, negative control)"
	@echo "make dry        show what installing would change, write nothing"
	@echo "make install    install into ~/.claude and report what is armed"
	@echo "make doctor     check which guards are armed right now"
	@echo "make uninstall  remove the hooks and their registrations"
	@echo "make lint       shellcheck the shell hooks (needs shellcheck)"
	@echo "make parity     regenerate settings.example.json from the manifest"

test:
	@bash tests/run.sh

dry:
	@./install.sh --dry-run

install:
	@./install.sh

uninstall:
	@./install.sh --uninstall

doctor:
	@./doctor.sh -v

lint:
	@shellcheck --severity=warning -e SC1090,SC1091,SC2016 \
		hooks/*.sh install.sh doctor.sh tests/run.sh

parity:
	@python3 tests/parity.py --write
