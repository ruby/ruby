# ZJIT: ADVANCED RUBY JIT PROTOTYPE

## Build Instructions

To build ZJIT on macOS:
```
./autogen.sh
./configure --disable-yjit --enable-zjit=dev --prefix=$HOME/.rubies/ruby-yjit --disable-install-doc --with-opt-dir="$(brew --prefix openssl):$(brew --prefix readline):$(brew --prefix libyaml)"
make -j miniruby
```

To run tests:
```
# You'll need to `brew install cargo-nextest` first:
make zjit-test
```

## Useful dev commands

To view YARV output for code snippets:
```
./miniruby --dump=insns --e0
```

To run code snippets with ZJIT:
```
./miniruby --zjit --e0
```

You can also try https://www.rubyexplorer.xyz/ to view Ruby YARV disasm output with syntax highlighting
in a way that can be easily shared with other team members.
