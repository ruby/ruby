# Ruby Hacking Guide

This document gives some helpful instructions which should make your experience as a Ruby core developer easier.

## Setup

### Make

It's common to want to compile things as quickly as possible. Ensuring `make` has the right `--jobs` flag will ensure all processors are utilized when building software projects. To do this effectively, you can set `MAKEFLAGS` in your shell configuration/profile:

``` shell
# On macOS with Fish shell:
export MAKEFLAGS="--jobs "(sysctl -n hw.ncpu)

# On macOS with Bash/ZSH shell:
export MAKEFLAGS="--jobs $(sysctl -n hw.ncpu)"

# On Linux with Fish shell:
export MAKEFLAGS="--jobs "(nproc)

# On Linux with Bash/ZSH shell:
export MAKEFLAGS="--jobs $(nproc)"
```

## Configure Ruby

It's generally advisable to use a build directory.

``` shell
./autogen.sh
mkdir build
cd build
../configure --prefix $HOME/.rubies/ruby-head
make install
```

### Without Documentation

If you are frequently building Ruby, this will reduce the time it takes to `make install`.

``` shell
../configure --disable-install-doc
```

## Running Ruby

### Run Local Test Script

You can create a file in the Ruby source root called `test.rb`. You can build `miniruby` and execute this script:

``` shell
make run
```

If you want more of the standard library, you can use `runruby` instead of `run`.

### Run Bootstrap Tests

There are a set of tests in `bootstraptest/` which cover most basic features of the core Ruby language.

``` shell
make test
```

### Run Extensive Tests

There are extensive tests in `test/` which cover a wide range of features of the Ruby core language.

``` shell
make test-all
```

You can run specific tests by specifying their path:

``` shell
make test-all TESTS=../test/fiber/test_io.rb
```

### Run RubySpec Tests

RubySpec is a project to write a complete, executable specification for the Ruby programming language.

``` shell
make test-all test-rubyspec
```
