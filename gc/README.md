# Ruby's Garbage Collectors

This directory contains implementations for Ruby's garbage collector (GC). The GC implementations use the Modular GC API to interact with Ruby. For more details about this API, see the [Modular GC API](#modular-gc-api) section.

Two GC implementations are included in Ruby:

- Default: The GC implementation that is used by default in Ruby. This GC is stable and production ready. The implementation uses a mark-sweep-compact algorithm.
- MMTk: An experimental implementation using the [MMTk](https://www.mmtk.io/) framework. The code lives in the [ruby/mmtk](https://github.com/ruby/mmtk) repository and is synchronized here. MMTk provides a [wide variety of GC algorithms](https://www.mmtk.io/status#implemented-collectors) to choose from. For usage instructions and current progress, refer to the [ruby/mmtk](https://github.com/ruby/mmtk) repository.

## Building guide

> [!TIP]
> If you are not sure how to build Ruby, follow the [Building Ruby](https://docs.ruby-lang.org/en/master/contributing/building_ruby_md.html) guide.

> [!IMPORTANT]
> Ruby's modular GC feature is experimental and subject to change. There may be bugs or performance impacts. Use at your own risk.

### Building Ruby with Modular GC

1. Configure Ruby with the `--with-modular-gc=<dir>` option, where `dir` is the directory you want to place the built GC libraries into.
2. Build Ruby as usual.

### Building GC implementations shipped with Ruby

1. Build your desired GC implementation with `make install-modular-gc MODULAR_GC=<impl>`. This will build the GC implementation and place the built library into the `dir` specified in step 1. `impl` can be one of:
    - `default`: The default GC that Ruby ships with.
    - `mmtk`: The GC that uses [MMTk](https://www.mmtk.io/) as the back-end. See Ruby-specific details in the [ruby/mmtk](https://github.com/ruby/mmtk) repository.
2. Run your desired GC implementation by setting the `RUBY_GC_LIBRARY=<lib>` environment variable, where `lib` could be `default`, `mmtk`, or your own implementation (as long as you place it in the `dir` specified in step 1).

## Modular GC API

> [!WARNING]
> The Modular GC API is experimental and subject to change without notice.

GC implementations interact with Ruby via the Modular GC API. All implementations must provide the functions in [gc/gc_impl.h](https://github.com/ruby/ruby/blob/master/gc/gc_impl.h) for Ruby to hook into. GC implementations can use any public C API in Ruby, along with additional APIs defined in [gc/gc.h](https://github.com/ruby/ruby/blob/master/gc/gc.h).

Additionally, create an extconf.rb file to build the GC library. This file must use [gc/extconf_base.rb](https://github.com/ruby/ruby/blob/master/gc/extconf_base.rb) and the `create_gc_makefile` method.
