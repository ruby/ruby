# NEWS for Ruby 3.2.0

This document is a list of user-visible feature changes
since the **3.1.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

* Anonymous rest and keyword rest arguments can now be passed as
  arguments, instead of just used in method parameters.
  [[Feature #18351]]

    ```ruby
    def foo(*)
      bar(*)
    end
    def baz(**)
      quux(**)
    end
    ```

## Command line options

## Core classes updates

Note: We're only listing outstanding class updates.

## Stdlib updates

*   The following default gem are updated.
    * RubyGems 3.4.0.dev
    * bundler 2.4.0.dev
    * io-console 0.5.11
*   The following bundled gems are updated.
    * typeprof 0.21.2
*   The following default gems are now bundled gems.

## Compatibility issues

Note: Excluding feature bug fixes.

### Removed methods

The following deprecated methods are removed.

* `Dir.exists?`
* `File.exists?`

## Stdlib compatibility issues

## C API updates

### Removed C APIs

The following deprecated APIs are removed.

* `rb_cData` variable.
* "taintedness" and "trustedness" functions.

## Implementation improvements

## JIT

### MJIT

### YJIT: New experimental in-process JIT compiler

## Static analysis

### RBS

### TypeProf

## Debugger

## error_highlight

## IRB Autocomplete and Document Display

## Miscellaneous changes

[Feature #18351]: https://bugs.ruby-lang.org/issues/18351
