# Building Ruby

## Dependencies

1. Install the prerequisite dependencies for building the CRuby interpreter:

    * C compiler

    For RubyGems, you will also need:

    * OpenSSL 1.1.x or 3.0.x / LibreSSL
    * libyaml 0.1.7 or later
    * zlib

    If you want to build from the git repository, you will also need:

    * autoconf - 2.67 or later
    * gperf - 3.1 or later
        * Usually unneeded; only if you edit some source files using gperf
    * ruby - 2.5 or later
        * We can upgrade this version to system ruby version of the latest Ubuntu LTS.

2. Install optional, recommended dependencies:

    * libffi (to build fiddle)
    * gmp (if you with to accelerate Bignum operations)
    * libexecinfo (FreeBSD)
    * rustc - 1.58.0 or later, if you wish to build
      [YJIT](https://docs.ruby-lang.org/en/master/RubyVM/YJIT.html).

    If you installed the libraries needed for extensions (openssl, readline, libyaml, zlib) into other than the OS default place,
    typically using Homebrew on macOS, add `--with-EXTLIB-dir` options to `CONFIGURE_ARGS` environment variable.

    ``` shell
    export CONFIGURE_ARGS=""
    for ext in openssl readline libyaml zlib; do
      CONFIGURE_ARGS="${CONFIGURE_ARGS} --with-$ext-dir=$(brew --prefix $ext)"
    done
    ```

## Quick start guide

1. Download ruby source code:

    Select one of the bellow.

    1. Build from the tarball:

        Download the latest tarball from [ruby-lang.org](https://www.ruby-lang.org/en/downloads/) and
        extract it. Example for Ruby 3.0.2:

        ``` shell
        tar -xzf ruby-3.0.2.tar.gz
        cd ruby-3.0.2
        ```

    2. Build from the git repository:

        Checkout the CRuby source code:

        ``` shell
        git clone https://github.com/ruby/ruby.git
        cd ruby
        ```

        Generate the configure file:

        ``` shell
        ./autogen.sh
        ```

2. Create a `build` directory separate from the source directory:

    ``` shell
    mkdir build && cd build
    ```

    While it's not necessary to build in a separate directory, it's good practice to do so.

3. We'll install Ruby in `~/.rubies/ruby-master`, so create the directory:

    ``` shell
    mkdir ~/.rubies
    ```

4. Run configure:

    ``` shell
    ../configure --prefix="${HOME}/.rubies/ruby-master"
    ```

    - If you are frequently building Ruby, add the `--disable-install-doc` flag to not build documentation which will speed up the build process.

    - Also `-C` (or `--config-cache`) would reduce time to configure from the next time.

5. Build Ruby:

    ``` shell
    make install
    ```

6. [Run tests](testing_ruby.md) to confirm your build succeeded.

### Unexplainable Build Errors

If you are having unexplainable build errors, after saving all your work, try running `git clean -xfd` in the source root to remove all git ignored local files. If you are working from a source directory that's been updated several times, you may have temporary build artifacts from previous releases which can cause build failures.

## Building on Windows

The documentation for building on Windows can be found [here](../windows.md).

## More details

If you're interested in continuing development on Ruby, here are more details
about Ruby's build to help out.

### Running make scripts in parallel

In GNU make and BSD make implementations, to run a specific make script in parallel, pass the flag `-j<number of processes>`. For instance,
to run tests on 8 processes, use:

``` shell
make test-all -j8
```

We can also set `MAKEFLAGS` to run _all_ `make` commands in parallel.

Having the right `--jobs` flag will ensure all processors are utilized when building software projects. To do this effectively, you can set `MAKEFLAGS` in your shell configuration/profile:

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

### Miniruby vs Ruby

Miniruby is a version of Ruby which has no external dependencies and lacks certain features.
It can be useful in Ruby development because it allows for faster build times. Miniruby is
built before Ruby. A functional Miniruby is required to build Ruby. To build Miniruby:

``` shell
make miniruby
```

## Debugging

You can use either lldb or gdb for debugging. Before debugging, you need to create a `test.rb`
with the Ruby script you'd like to run. You can use the following make targets:

* `make run`: Runs `test.rb` using Miniruby
* `make lldb`: Runs `test.rb` using Miniruby in lldb
* `make gdb`: Runs `test.rb` using Miniruby in gdb
* `make runruby`: Runs `test.rb` using Ruby
* `make lldb-ruby`: Runs `test.rb` using Ruby in lldb
* `make gdb-ruby`: Runs `test.rb` using Ruby in gdb

### Compiling for Debugging

You should configure Ruby without optimization and other flags that may interfere with debugging:

``` shell
./configure --enable-debug-env optflags="-O0 -fno-omit-frame-pointer"
```

### Building with Address Sanitizer

Using the address sanitizer is a great way to detect memory issues.

``` shell
./autogen.sh
mkdir build && cd build
export ASAN_OPTIONS="halt_on_error=0:use_sigaltstack=0:detect_leaks=0"
../configure cppflags="-fsanitize=address -fno-omit-frame-pointer" optflags=-O0 LDFLAGS="-fsanitize=address -fno-omit-frame-pointer"
make
```

On Linux it is important to specify `-O0` when debugging. This is especially true for ASAN which sometimes works incorrectly at higher optimisation levels.

## How to measure coverage of C and Ruby code

You need to be able to use gcc (gcov) and lcov visualizer.

``` shell
./autogen.sh
./configure --enable-gcov
make
make update-coverage
rm -f test-coverage.dat
make test-all COVERAGE=true
make lcov
open lcov-out/index.html
```

If you need only C code coverage, you can remove `COVERAGE=true` from the above process.
You can also use `gcov` command directly to get per-file coverage.

If you need only Ruby code coverage, you can remove `--enable-gcov`.
Note that `test-coverage.dat` accumulates all runs of `make test-all`.
Make sure that you remove the file if you want to measure one test run.

You can see the coverage result of CI: https://rubyci.org/coverage
