MicroJIT (uJIT)
===============

**DISCLAIMER: Please note that this project is in early stages of development. It is very much a work in progress, it may cause your software to crash, and current performance results are likely to leave you feeling unimpressed.**

MicroJIT is a lightweight, minimalistic Ruby JIT built inside the CRuby/MRI binary.
It lazily compiles code using a Basic Block Versioning (BBV) architecture. The target use case is that of servers running
Ruby on Rails, an area where CRuby's MJIT has not yet managed to deliver speedups. 
To simplify development, we currently support only MacOS and Linux on x86-64, but an ARM64 backend
is part of future plans.
This project is open source and falls under the same license as CRuby.

If you would like to learn more about BBV, there are two published papers, and associated conference talks:
- [Simple and Effective Type Check Removal through Lazy Basic Block Versioning](https://arxiv.org/pdf/1411.0352.pdf) ([ECOOP 2015 talk](https://www.youtube.com/watch?v=S-aHBuoiYE0))
- [Interprocedural Type Specialization of JavaScript Programs Without Type Analysis](https://drops.dagstuhl.de/opus/volltexte/2016/6101/pdf/LIPIcs-ECOOP-2016-7.pdf) ([ECOOP 2016 talk](https://www.youtube.com/watch?v=sRNBY7Ss97A))

## Installation

Start by cloning the `microjit` branch of the `Shopify/ruby` repository:

```
git clone https://github.com/Shopify/ruby.git microjit
cd microjit
git checkout microjit
```

The uJIT `ruby` binary can be built with either GCC or Clang. We recommend enabling debug symbols so that assertions are enabled:

```
autoconf
./configure cppflags=-DRUBY_DEBUG --prefix=$HOME/.rubies/ruby-microjit
make -j16 install
```

You can test that uJIT works correctly by running:

```
# Quick tests found in /bootstraptest
make btest

# Complete set of tests
make -j16 test-all
```

Once uJIT is built, you can either use `./miniruby` from within your build directory, or switch to the uJIT version of `ruby`
by using the `chruby` tool:

```
chruby ruby-microjit
```

## Source Code Organization

The uJIT source code is divided between:
- `ujit_asm.c`: x86 in-memory assembler we use to generate machine code
- `ujit_codegen.c`: logic for translating Ruby bytecode to machine code
- `ujit_core.c`: basic block versioning logic, core structure of uJIT
- `ujit_iface.c`: code uJIT uses to interface with the rest of CRuby
- `ujit.rb`: `UJIT` module that is exposed to Ruby code

The core of CRuby's interpreter logic is found in:
- `insns.def`: defines Ruby's bytecode instructions
- `vm_insnshelper.c`: logic used by Ruby's bytecode instructions
- `vm_exec.c`: Ruby interpreter loop

## Contributing

We welcome open source contributors. If you are interested in contributing to this project, please contact Maxime Chevalier [(@Love2Code) via twitter](https://twitter.com/Love2Code).
