# Building Ruby

## Quick start guide

1. Install the prerequisite dependencies for building the CRuby interpreter:

    * C compiler
    * autoconf - 2.67 or later
    * bison - 2.0 or later
    * gperf - 3.0.3 or later
    * ruby - 2.7 or later

2. Install optional, recommended dependencies:

    * OpenSSL/LibreSSL
    * readline/editline (libedit)
    * zlib
    * libffi
    * libyaml
    * libexecinfo (FreeBSD)

3. Checkout the CRuby source code:

    ```
    git clone https://github.com/ruby/ruby.git
    ```

4. Generate the configuration files and build:

    ```
    ./autogen.sh
    mkdir build && cd build # its good practice to build outside of source dir
    mkdir ~/.rubies # we will install to .rubies/ruby-master in our home dir
    ../configure --prefix="${HOME}/.rubies/ruby-master"
    make install
    ```

5. [Run tests](testing_ruby.md) to confirm your build succeeded

## More details

If you're interested in continuing development on Ruby, here are more details
about Ruby's build to help out.

### Running make scripts in parallel

To run make scripts in parallel, pass flag `-j<number of processes>`. For instance,
to run tests on 8 processes, use:

```
make test-all -j8
```

### Miniruby vs Ruby

Miniruby is a version of Ruby which has no external dependencies and lacks certain features.
It can be useful in Ruby development because it allows for faster build times. Miniruby is
built before Ruby. A functional Miniruby is required to build Ruby. To build Miniruby:

```
make miniruby
```

## Debugging

You can use either lldb or gdb for debugging. Before debugging, you need to create a `test.rb`
with the Ruby script you'd like to run. You can use the following make targets:

* `make run`: Runs `test.rb` using Miniruby
* `make lldb`: Runs `test.rb` using Miniruby in lldb
* `make gdb`: Runs `test.rb` using Miniruby in gdb
* `make runruby`: Runs `test.rb` using Ruby
* `make lldb-runruby`: Runs `test.rb` using Ruby in lldb
* `make gdb-runruby`: Runs `test.rb` using Ruby in gdb
