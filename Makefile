.PHONY: test lint fmt fmt-check

test:
	./scripts/test

lint:
	luacheck lua/ tests/ repro.lua

fmt:
	stylua lua/ tests/ repro.lua

fmt-check:
	stylua --check lua/ tests/ repro.lua
