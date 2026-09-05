# Default recipe
default: lint

# Run all linter checks (StyLua, Selene, Lua Language Server)
lint:
    stylua --check .
    selene .
    lua-language-server --check .

# Auto-format Lua codebase
format:
    stylua .

# Run headless test suite
test:
    nvim --headless -u NONE -c 'set noswapfile' -c 'set runtimepath+=.' -c 'luafile tests/test_spec.lua'

# Run both lint and test
check: lint test
