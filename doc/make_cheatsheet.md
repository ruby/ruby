# How to use "configure" and "make" commands for Ruby

This is for developers of Ruby.
If you are a user of Ruby, please see README.md.

## In-place build

```
$ autoconf
$ ./configure --prefix=$PWD/local
$ make
$ make install
$ ./local/bin/ruby -e 'puts "Hello"'
Hello
```

## Out-of-place build

```
$ autoconf
$ mkdir ../ruby-build
$ cd ../ruby-build
$ ../ruby-src/configure --prefix=$PWD/local
$ make
$ make install
$ ./local/bin/ruby -e 'puts "Hello"'
Hello
```

## How to run the whole test suite

```
$ make check
```

It runs (about) three test suites:

* `make test` (a test suite for the interpreter core)
* `make test-all` (for all builtin classes and libraries)
* `make test-spec` (a conformance test suite for Ruby implementations)
* `make test-bundler` (a test suite for the bundler examples)

## How to run the test suite with log

```
$ make test OPTS=-v

$ make test-all TESTS=-v

$ make test-spec MSPECOPT=-Vfs
```

## How to run a part of the test suite

### Runs a directory
```
$ make test-all TESTS=test/rubygems
$ make test-all TESTS=rubygems
```

### Runs a file
```
$ make test-all TESTS=test/ruby/test_foo.rb
$ make test-all TESTS=ruby/foo
```

### Runs a test whose name includes test_bar
```
$ make test-all TESTS="test/ruby/test_foo.rb -n /test_bar/"
```

### Runs a file or directory with GNU make
```
$ make test/ruby/test_foo.rb
$ make test/ruby/test_foo.rb TESTOPTS="-n /test_bar/"
```

### Runs a ruby-spec directory
```
$ make test-spec MSPECOPT=spec/ruby/core/foo
```

### Runs a ruby-spec file
```
$ make test-spec MSPECOPT=spec/ruby/core/foo/bar_spec.rb
```

### Runs a ruby-spec file or directory with GNU make
```
$ make spec/ruby/core/foo/bar_spec.rb
```

### Runs a bundler spec file
```
$ make test-bundler BUNDLER_SPECS=commands/exec_spec.rb:58
```

## How to measure coverage of C and Ruby code

You need to be able to use gcc (gcov) and lcov visualizer.

```
$ autoconf
$ ./configure --enable-gcov
$ make
$ make update-coverage
$ rm -f test-coverage.dat
$ make test-all COVERAGE=true
$ make lcov
$ open lcov-out/index.html
```

If you need only C code coverage, you can remove `COVERAGE=true` from the above process.
You can also use `gcov` command directly to get per-file coverage.

If you need only Ruby code coverage, you can remove `--enable-gcov`.
Note that `test-coverage.dat` accumulates all runs of `make test-all`.
Make sure that you remove the file if you want to measure one test run.

You can see the coverage result of CI: https://rubyci.org/coverage

## How to benchmark

see https://github.com/ruby/ruby/tree/master/benchmark#make-benchmark
