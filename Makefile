PREFIX ?= $(HOME)/.local
SWIFTC = swiftc -O -swift-version 5

install:
	mkdir -p $(PREFIX)/bin
	$(SWIFTC) Sources/*.swift -o $(PREFIX)/bin/remind

test:
	mkdir -p .build
	$(SWIFTC) Sources/Parse.swift Tests/main.swift -o .build/remind-tests
	.build/remind-tests

.PHONY: install test
