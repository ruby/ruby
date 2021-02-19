MicroJIT (uJIT)
===============

MicroJIT is a lightweight, minimalistic Ruby JIT built inside the CRuby/MRI binary.
It lazily compiles code using a Basic Block Versioning (BBV) architecture. The target use case is that of servers running
Ruby on Rails, an area where CRuby's MJIT has not yet managed to deliver speedups. 
To simplify development, we currently support only MacOS and Linux on x86-64, but an ARM64 backend
is part of future plans.
This project is open source and falls under the same license as CRuby.

## Installation

The uJIT `ruby` binary can be built with either GCC or Clang.  We recommend enabling debug symbols so that assertions are enabled

```
autoconf
./configure cppflags=-DRUBY_DEBUG --prefix=$HOME/.rubies/ruby-microjit
make -j16 install
```

Once uJIT is built, you can either use `./miniruby` from within your build directory, or switch to the uJIT version of `ruby`
by using the `chruby` tool:

```
chruby ruby-microjit
```

## Source Code Organization

## Contributing

If you are interested in contributing to this project, please contact Maxime Chevalier [(@Love2Code) via twitter](https://twitter.com/Love2Code).
