# ruby/benchmark

This directory has benchmark definitions to be run with
[benchmark\_driver.gem](https://github.com/benchmark-driver/benchmark-driver).

## Normal usage

Execute `gem install benchmark_driver` and run a command like:

```bash
# Run a benchmark script with the ruby in the $PATH
benchmark-driver benchmark/app_fib.rb

# Run benchmark scripts with multiple Ruby executables or options
benchmark-driver benchmark/*.rb -e /path/to/ruby -e '/path/to/ruby --jit'

# Or compare Ruby versions managed by rbenv
benchmark-driver benchmark/*.rb --rbenv '2.5.1;2.6.0-preview2 --jit'

# You can collect many metrics in many ways
benchmark-driver benchmark/*.rb --runner memory --output markdown

# Some are defined with YAML for complex setup or accurate measurement
benchmark-driver benchmark/*.yml
```

See also:

```console
Usage: benchmark-driver [options] RUBY|YAML...
    -r, --runner TYPE                Specify runner type: ips, time, memory, once, block (default: ips)
    -o, --output TYPE                Specify output type: compare, simple, markdown, record, all (default: compare)
    -e, --executables EXECS          Ruby executables (e1::path1 arg1; e2::path2 arg2;...)
        --rbenv VERSIONS             Ruby executables in rbenv (x.x.x arg1;y.y.y arg2;...)
        --repeat-count NUM           Try benchmark NUM times and use the fastest result or the worst memory usage
        --repeat-result TYPE         Yield "best", "average" or "worst" result with --repeat-count (default: best)
        --alternate                  Alternate executables instead of running the same executable in a row with --repeat-count
        --bundler                    Install and use gems specified in Gemfile
        --filter REGEXP              Filter out benchmarks with given regexp
        --run-duration SECONDS       Warmup estimates loop_count to run for this duration (default: 3)
        --timeout SECONDS            Timeout ruby command execution with timeout(1)
    -v, --verbose                    Verbose mode. Multiple -v options increase visilibity (max: 2)
```

## make benchmark

Using `make benchmark`, `make update-benchmark-driver` automatically downloads
the supported version of benchmark\_driver, and it runs benchmarks with the downloaded
benchmark\_driver.

```bash
# Run all benchmarks with the ruby in the $PATH and the built ruby
make benchmark

# Or compare with specific ruby binary
make benchmark COMPARE_RUBY="/path/to/ruby --jit"

# Run vm benchmarks
make benchmark ITEM=vm

# Run some limited benchmarks in ITEM-matched files
make benchmark ITEM=vm OPTS=--filter=block

# You can specify the benchmark by an exact filename instead of using the default argument:
# ARGS = $$(find $(srcdir)/benchmark -maxdepth 1 -name '*$(ITEM)*.yml' -o -name '*$(ITEM)*.rb')
make benchmark ARGS=benchmark/erb_render.yml

# You can specify any option via $OPTS
make benchmark OPTS="--help"

# With `make benchmark`, some special runner plugins are available:
#   -r peak, -r size, -r total, -r utime, -r stime, -r cutime, -r cstime
make benchmark ITEM=vm_bigarray OPTS="-r peak"
```
