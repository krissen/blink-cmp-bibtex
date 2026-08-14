.PHONY: test lint fmt fmt-check

test:
	./scripts/test

lint:
	luacheck lua/ plugin/ tests/ repro.lua

fmt:
	stylua lua/ plugin/ tests/ repro.lua

fmt-check:
	stylua --check lua/ plugin/ tests/ repro.lua
