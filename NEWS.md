# NEWS for Ruby 3.5.0

This document is a list of user-visible feature changes
since the **3.4.0** release, except for bug fixes.

Note that each entry is kept to a minimum, see links for details.

## Language changes

## Core classes updates

Note: We're only listing outstanding class updates.

* Binding

    * `Binding#local_variables` does no longer include numbered parameters.
      Also, `Binding#local_variable_get` and `Binding#local_variable_set` reject to handle numbered parameters.
      [[Bug #21049]]

## Stdlib updates

The following bundled gems are promoted from default gems.

* ostruct 0.6.1
* pstore 0.2.0
* benchmark 0.4.0
* logger 1.6.6
* rdoc 6.12.0
* win32ole 1.9.1
* irb 1.15.1
* reline 0.6.0
* readline 0.0.4
* fiddle 1.1.6

We only list stdlib changes that are notable feature changes.

Other changes are listed in the following sections. we also listed release history from the previous bundled version that is Ruby 3.3.0 if it has GitHub releases.

The following default gem is added.

* win32-registry 0.1.0

The following default gems are updated.

* RubyGems 3.7.0.dev
* bundler 2.7.0.dev
* cgi 0.4.2
* json 2.10.2
* optparse 0.7.0.dev.1
* prism 1.3.0
* psych 5.2.3
* stringio 3.1.6.dev
* uri 1.0.3

The following bundled gems are added.


The following bundled gems are updated.

* minitest 5.25.5
* rexml 3.4.1
* net-imap 0.5.6
* net-smtp 0.5.1
* rbs 3.8.1
* bigdecimal 3.1.9
* syslog 0.3.0
* repl_type_completor 0.1.10

## Supported platforms

## Compatibility issues

## Stdlib compatibility issues

## C API updates

## Implementation improvements

## JIT

[Bug #21049]:     https://bugs.ruby-lang.org/issues/21049
