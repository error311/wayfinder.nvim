NVIM ?= nvim
XDG_STATE_HOME ?= /tmp/wayfinder-state
XDG_CACHE_HOME ?= /tmp/wayfinder-cache
NVIM_LOG_FILE ?= /tmp/wayfinder-nvim.log

.PHONY: test
test:
	XDG_STATE_HOME=$(XDG_STATE_HOME) XDG_CACHE_HOME=$(XDG_CACHE_HOME) NVIM_LOG_FILE=$(NVIM_LOG_FILE) \
	$(NVIM) --headless -u NONE -i NONE \
		"+set shada=" \
		"+set noswapfile" \
		"+lua dofile('tests/run.lua')" \
		"+qa!"
