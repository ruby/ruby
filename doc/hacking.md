# Ruby Hacking Guide

This document gives some helpful instructions which should make your experience as a Ruby core developer easier.

## Setup

### Make

It's common to want to compile things as quickly as possible. Ensuring `make` has the right `--jobs` flag will ensure all processors are utilized when building software projects To do this effectively, you can set `MAKEFLAGS` in your shell configuration/profile:

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

### Unexplainable Build Errors

If you are having unexplainable build errors, after saving all your work, try running `git clean -xfd` in the source root to remove all git ignored local files. If you are working from a source directory that's been updated several times, you may have temporary build artefacts from previous releases which can cause build failures.

## Running Ruby

### Run Local Test Script

You can create a file in the Ruby source root called `test.rb`. You can build `miniruby` and execute this script:

``` shell
make run
```

If you want more of the standard library, you can use `runruby` instead of `run`.

## Running Tests

You can run the following tests at once:

``` shell
make check
```

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

### Run Ruby Spec Suite Tests

The [Ruby Spec Suite](https://github.com/ruby/spec/) is a test suite that aims to provide an executable description for the behaviour of the language.

``` shell
make test-spec
```

### Building with Address Sanitizer

Using the address sanitizer is a great way to detect memory issues.

``` shell
> ./autogen.sh
> mkdir build && cd build
> export ASAN_OPTIONS="halt_on_error=0:use_sigaltstack=0:detect_leaks=0"
> ../configure cppflags="-fsanitize=address -fno-omit-frame-pointer" optflags=-O0 LDFLAGS="-fsanitize=address -fno-omit-frame-pointer"
> make
```

On Linux it is important to specify -O0 when debugging and this is especially true for ASAN which sometimes works incorrectly at higher optimisation levels.
