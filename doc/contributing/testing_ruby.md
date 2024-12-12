# Testing Ruby

All the commands below assume that you're running them from the `build/` directory made during [Building Ruby](building_ruby.md).

## Test suites

There are several test suites in the Ruby codebase:

We can run any of the make scripts [in parallel](building_ruby.md#label-Running+make+scripts+in+parallel) to speed them up.

1. [bootstraptest/](https://github.com/ruby/ruby/tree/master/bootstraptest)

    This is a small test suite that runs on Miniruby (see [building Ruby](building_ruby.md#label-Miniruby+vs+Ruby)). We can run it with:

    ```sh
    make btest
    ```

    To run individual bootstrap tests, we can either specify a list of filenames or use the `--sets` flag in the variable `BTESTS`:

    ```sh
    make btest BTESTS="../bootstraptest/test_string.rb ../bootstraptest/test_class.rb"
    make btest BTESTS="--sets=string,class"
    ```

    To run these tests with verbose logging, we can add `-v` to the `OPTS`:

    ```sh
    make btest OPTS="--sets=string,class -v"
    ```

    If we want to run the bootstrap test suite on Ruby (not Miniruby), we can use:

    ```sh
    make test
    ```

    To run these tests with verbose logging, we can add `-v` to the `OPTS`:

    ```sh
    make test OPTS=-v
    ```

    To run a file or directory with GNU make, we can use:

    ```sh
    make ../test/ruby/test_string.rb
    make ../test/ruby/test_string.rb TESTOPTS="-n /test_.*_to_s/"
    ```

2. [test/](https://github.com/ruby/ruby/tree/master/test)

    This is a more comprehensive test suite that runs on Ruby. We can run it with:

    ```sh
    make test-all
    ```

    We can run a specific test directory in this suite using the `TESTS` option, for example:

    ```sh
    make test-all TESTS="../test/ruby/"
    ```

    We can run a specific test file in this suite by also using the `TESTS` option, for example:

    ```sh
    make test-all TESTS="../test/ruby/test_string.rb"
    ```

    We can run a specific test in this suite using the `TESTS` option, specifying
    first the file name, and then the test name, prefixed with `--name`. For example:

    ```sh
    make test-all TESTS="../test/ruby/test_string.rb --name=TestString#test_to_s"
    ```

    To run these tests with verbose logging, we can add `-v` to `TESTS`:

    ```sh
    make test-all TESTS=-v
    ```

    We can display the help of the `TESTS` option:

    ```sh
    make test-all TESTS=--help
    ```

    If we would like to run the `test/`, `bootstraptest/` and `spec/` test suites (the `spec/` is explained in a later section), we can run

    ```sh
    make check
    ```

3. [spec/ruby](https://github.com/ruby/ruby/tree/master/spec/ruby)

    This is a test suite that exists in [the Ruby spec repository](https://github.com/ruby/spec) and is mirrored into the `spec/ruby` directory in the Ruby repository. It tests the behavior of the Ruby programming language. We can run this using:

    ```sh
    make test-spec
    ```

    To run a specific directory, we can use `SPECOPTS` to specify the directory:

    ```sh
    make test-spec SPECOPTS="../spec/ruby/core/string/"
    ```

    To run a specific file, we can also use `SPECOPTS` to specify the file:

    ```sh
    make test-spec SPECOPTS="../spec/ruby/core/string/to_s_spec.rb"
    ```

    To run a specific test, we can use the `--example` flag to match against the test name:

    ```sh
    make test-spec SPECOPTS="../spec/ruby/core/string/to_s_spec.rb --example='returns self when self.class == String'"
    ```

    To run these specs with verbose logging, we can add `-v` to the `SPECOPTS`:

    ```sh
    make test-spec SPECOPTS="../spec/ruby/core/string/to_s_spec.rb -Vfs"
    ```

    To run a ruby-spec file or directory with GNU make, we can use

    ```sh
    make ../spec/ruby/core/string/to_s_spec.rb
    ```

4. [spec/bundler](https://github.com/ruby/ruby/tree/master/spec/bundler)

    The bundler test suite exists in [the RubyGems repository](https://github.com/rubygems/rubygems/tree/master/bundler/spec) and is mirrored into the `spec/bundler` directory in the Ruby repository. We can run this using:

    ```sh
    make test-bundler
    ```

    To run a specific bundler spec file, we can use `BUNDLER_SPECS` as follows:

    ```sh
    make test-bundler BUNDLER_SPECS=commands/exec_spec.rb
    ```

## Troubleshooting

### Running test suites on s390x CPU Architecture

If we see failing tests related to the zlib library on s390x CPU architecture, we can run the test suites with `DFLTCC=0` to pass:

```sh
DFLTCC=0 make check
```

The failures can happen with the zlib library applying the patch [madler/zlib#410](https://github.com/madler/zlib/pull/410) to enable the deflate algorithm producing a different compressed byte stream. We manage this issue at [[ruby-core:114942][Bug #19909]](https://bugs.ruby-lang.org/issues/19909).
