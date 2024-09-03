test:
	tsc -f tests/*.lua

test-deps:
	luarocks install telescope

deps:
	luarocks install luasocket
	luarocks install lua-cjson
	luarocks install uuid
	luarocks install luasec

.PHONY: test test-deps deps
