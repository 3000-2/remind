PREFIX ?= $(HOME)/.local

install:
	swift build -c release
	mkdir -p $(PREFIX)/bin
	install .build/release/remind $(PREFIX)/bin/remind

test:
	env -u REMIND_E2E swift test

check: lint test

e2e:
	REMIND_E2E=1 swift test --filter EndToEnd

format:
	swift format --in-place --recursive Package.swift Sources Tests

lint:
	swift format lint --strict --recursive Package.swift Sources Tests

.PHONY: install test check e2e format lint
