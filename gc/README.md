# Ruby's Garbage Collectors

TODO introduction.

## Building guide

> [!TIP]
> If you are not sure how to build Ruby, follow the [Building Ruby](https://docs.ruby-lang.org/en/master/contributing/building_ruby_md.html) guide.

> [!IMPORTANT]
> Ruby's modular GC feature is experimental and subject to change. There may be bugs or performance impacts. Use at your own risk.

1. Configure Ruby with `--with-modular-gc=<dir>`, where `dir` is the directory you want to place the built GC libraries into.
2. Build Ruby as usual.
3. Build your desired GC implementation with `make modular-gc MODULAR_GC=<impl>`. This will build the GC implementation and place the built library into the `dir` specified in step 1. `impl` can be one of:
    - `default`: The default GC that Ruby ships with.
    - `mmtk`: The GC that uses [MMTk](https://www.mmtk.io/) as the back-end. See Ruby specific details in the [ruby/mmtk](https://github.com/ruby/mmtk) repository.
4. Run with your built GC implementation using the `RUBY_GC_LIBRARY=<lib>` environment variable, where `lib` could be `default`, `mmtk`, or your own implementation (as long as you place it in the `dir` specified in step 1).
