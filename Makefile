SHELL := /bin/bash

.PHONY: validate check register unregister start stop restart status verify cleanup update logs test-telegram survey-before survey-after survey-during

validate:
	./scripts/validate-package.sh

check:
	./scripts/check-prerequisites.sh

register:
	./scripts/register-runners.sh

unregister:
	./scripts/unregister-runners.sh

start:
	./scripts/start.sh

stop:
	./scripts/stop.sh

restart:
	./scripts/restart.sh

status:
	./scripts/status.sh

verify:
	./scripts/verify-installation.sh

cleanup:
	sudo ./scripts/cleanup.sh

update:
	./scripts/update.sh

logs:
	docker compose logs --tail=200 -f

test-telegram:
	sudo ./scripts/test-telegram.sh

survey-before:
	./scripts/host-survey.sh before

survey-after:
	./scripts/host-survey.sh after-idle

survey-during:
	./scripts/host-survey.sh during-ci
