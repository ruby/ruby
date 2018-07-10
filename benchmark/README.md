# ruby/benchmark

This directory has benchmark definitions to be run with
[benchmark\_driver.gem](https://github.com/benchmark-driver/benchmark-driver).

## Normal usage

Execute `gem install benchmark-driver` and run a command like:

```bash
# Run a benchmark script with the ruby in the $PATH
benchmark-driver benchmark/erb_render.yml

# Run all benchmark scripts with multiple Ruby executables or options
benchmark-driver benchmark/*.yml -e /path/to/ruby -e '/path/to/ruby --jit'

# Or compare Ruby versions managed by rbenv
benchmark-driver benchmark/*.yml --rbenv '2.5.1;2.6.0-preview2 --jit'
```

## make benchmark

Using `make benchmark`, `make update-benchmark-driver` automatically downloads
the supported version of benchmark-driver, and it runs benchmarks with the downloaded
benchmark-driver.

```bash
# Run all benchmarks with the ruby in the $PATH and the built ruby
make benchmark

# Or compare with specific ruby binary
make benchmark COMPARE_RUBY="/path/to/ruby --jit"

# Run vm1 benchmarks
make benchmark ITEM=vm1

# Run some limited benchmarks in ITEM-matched files
make benchmark ITEM=vm1 OPTS=--filter=block

# You can specify the benchmark by an exact filename instead of using the default argument:
# ARGS = $$(find $(srcdir)/benchmark -maxdepth 1 -name '*$(ITEM)*.yml' -o -name '*$(ITEM)*.rb')
make benchmark ARGS=../benchmark/erb_render.yml

# You can specify any option via $OPTS
make benchmark OPTS="--help"

# With `make benchmark`, some special runner plugins are available:
#   -r peak, -r size
make benchmark ITEM=vm2_bigarray OPTS="-r peak"
```
