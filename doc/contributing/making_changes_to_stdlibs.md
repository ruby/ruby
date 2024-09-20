# Making Changes To Standard Libraries

Everything in the [lib](https://github.com/ruby/ruby/tree/master/lib) directory is mirrored from a standalone repository into the Ruby repository.
If you'd like to make contributions to standard libraries, do so in the standalone repositories, and the
changes will be automatically mirrored into the Ruby repository.

For example, CSV lives in [a separate repository](https://github.com/ruby/csv) and is mirrored into [Ruby](https://github.com/ruby/ruby/tree/master/lib/csv).

## Maintainers

You can find the list of maintainers [here](https://docs.ruby-lang.org/en/master/maintainers_md.html#label-Maintainers).

## Build

First, install its dependencies using:

```
bundle install
```

### Libraries with C-extension

If the library has a `/ext` directory, it has C files that you need to compile with:

```
bundle exec rake compile
```

## Running tests

All standard libraries use [test-unit](https://github.com/test-unit/test-unit) as the test framework.

To run all tests:

```
bundle exec rake test
```

To run a single test file:

```
bundle exec rake test TEST="test/test_foo.rb"
```

To run a single test case:

```
bundle exec rake test TEST="test/test_foo.rb" TESTOPS="--name=/test_mytest/"
```
