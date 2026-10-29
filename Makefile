PREFIX ?= $(HOME)/.local

install:
	mkdir -p $(PREFIX)/bin
	swiftc -O main.swift -o $(PREFIX)/bin/remind

.PHONY: install
