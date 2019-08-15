# The Ruby Spec Suite

[![Build Status](https://travis-ci.org/ruby/spec.svg)](https://travis-ci.org/ruby/spec)
[![Build Status](https://ci.appveyor.com/api/projects/status/1gs6f399320o44b1?svg=true)](https://ci.appveyor.com/project/eregon/spec-x948i)
[![Gitter](https://badges.gitter.im/ruby/spec.svg)](https://gitter.im/ruby/spec)

The Ruby Spec Suite, abbreviated `ruby/spec`, is a test suite for the behavior of the Ruby programming language.

It is not a standardized specification like the ISO one, and does not aim to become one.
Instead, it is a practical tool to describe and test the behavior of Ruby with code.

Every example code has a textual description, which presents several advantages:

* It is easier to understand the intent of the author
* It documents how recent versions of Ruby should behave
* It helps Ruby implementations to agree on a common behavior

The specs are written with syntax similar to RSpec 2.
They are run with MSpec, the purpose-built framework for running the Ruby Spec Suite.
For more information, see the [MSpec](http://github.com/ruby/mspec) project.

The specs describe the [language syntax](language/), the [core library](core/), the [standard library](library/), the [C API for extensions](optional/capi) and the [command line flags](command_line/).
The language specs are grouped by keyword while the core and standard library specs are grouped by class and method.

ruby/spec is known to be tested in these implementations for every commit:
* [MRI](http://rubyci.org/) on 30 platforms and 4 versions
* [JRuby](https://github.com/jruby/jruby/tree/master/spec/ruby) for both 1.7 and 9.x
* [TruffleRuby](https://github.com/oracle/truffleruby/tree/master/spec/ruby)
* [Opal](https://github.com/opal/opal/tree/master/spec)

ruby/spec describes the behavior of Ruby 2.4 and more recent Ruby versions.
More precisely, every latest stable MRI release should [pass](https://travis-ci.org/ruby/spec) all specs of ruby/spec (2.4.x, 2.5.x, 2.6.x, etc), and those are tested in TravisCI.

The specs are synchronized both ways around once a month by @eregon between ruby/spec, MRI, JRuby and TruffleRuby.
Each of these repositories has a full copy of the specs under `spec/ruby` to ease editing specs.
Any of these repositories can be used to add or edit specs, use what is most convenient for you.

For *testing* a Ruby implementation, one should always test against the implementation's copy of the specs under `spec/ruby`, as that's what the Ruby implementation tests against in their CI.
Also, this repository doesn't always contain the latest spec changes from MRI (it's synchronized monthly), and does not contain tags (specs marked as failing on that Ruby implementation).
Running specs in a Ruby implementation can be done with:

```
$ cd ruby_implementation/spec/ruby
# Add ../ruby_implementation/bin in PATH, or pass -t /path/to/bin/ruby
$ ../mspec/bin/mspec
```

For older specs try these commits:
* Ruby 2.0.0-p647 - [Suite](https://github.com/ruby/spec/commit/245862558761d5abc676843ef74f86c9bcc8ea8d) using [MSpec](https://github.com/ruby/mspec/commit/f90efa068791064f955de7a843e96e2d7d3041c2) (may encounter 2 failures)
* Ruby 2.1.9 - [Suite](https://github.com/ruby/spec/commit/f029e65241374386077ac500add557ae65069b55) using [MSpec](https://github.com/ruby/mspec/commit/55568ea3918c6380e64db8c567d732fa5781efed)
* Ruby 2.2.10 - [Suite](https://github.com/ruby/spec/commit/cbaa0e412270c944df0c2532fc500c920dba0e92) using [MSpec](https://github.com/ruby/mspec/commit/d84d7668449e96856c5f6bac8cb1526b6d357ce3)
* Ruby 2.3.8 - [Suite](https://github.com/ruby/spec/commit/dc733114d8ae66a3368ba3a98422c50147a76ba5) using [MSpec](https://github.com/ruby/mspec/commit/4599bc195fb109f2a482a01c32a7d659518369ea)

### Running the specs

First, clone this repository:

    $ git clone https://github.com/ruby/spec.git

Then move to it:

    $ cd spec

Clone [MSpec](http://github.com/ruby/mspec):

    $ git clone https://github.com/ruby/mspec.git ../mspec

And run the spec suite:

    $ ../mspec/bin/mspec

This will execute all the specs using the executable named `ruby` on your current PATH.

### Running Specs with a Specific Ruby Implementation

Use the `-t` option to specify the Ruby implementation with which to run the specs.
The argument is either a full path to the Ruby binary, or an executable in `$PATH`.

    $ ../mspec/bin/mspec -t /path/to/some/bin/ruby

### Running Selected Specs

To run a single spec file, pass the filename to `mspec`:

    $ ../mspec/bin/mspec core/kernel/kind_of_spec.rb

You can also pass a directory, in which case all specs in that directories will be run:

    $ ../mspec/bin/mspec core/kernel

Finally, you can also run them per group as defined in `default.mspec`.
The following command will run all language specs:

    $ ../mspec/bin/mspec :language

In similar fashion, the following commands run the respective specs:

    $ ../mspec/bin/mspec :core
    $ ../mspec/bin/mspec :library
    $ ../mspec/bin/mspec :capi

### Sanity Checks When Running Specs

A number of checks for various kind of "leaks" (file descriptors, temporary files,
threads, subprocesses, `ENV`, `ARGV`, global encodings, top-level constants) can be
enabled with `CHECK_LEAKS=true`:

    $ CHECK_LEAKS=true ../mspec/bin/mspec

New top-level constants should only be introduced when needed or follow the
pattern `<ClassBeingTested>Specs` such as `module StringSpecs`.
Other constants used for testing should be nested under such a module.

Exceptions to these rules are contained in the file `.mspec.constants`.
MSpec can automatically add new top-level constants in this file with:

    $ CHECK_LEAKS=save mspec ../mspec/bin/mspec file

### Contributing and Writing Specs

See [CONTRIBUTING.md](https://github.com/ruby/spec/blob/master/CONTRIBUTING.md) for documentation about contributing and writing specs (guards, matchers, etc).

### Socket specs from rubysl-socket

Most specs under `library/socket` were imported from [the rubysl-socket project](https://github.com/rubysl/rubysl-socket).
The 3 copyright holders of rubysl-socket, Yorick Peterse, Chuck Remes and
Brian Shirai, [agreed to relicense those specs](https://github.com/rubysl/rubysl-socket/issues/15)
under the MIT license in ruby/spec.

### History and RubySpec

This project was originally born from [Rubinius](https://github.com/rubinius/rubinius) tests being converted to the spec style.
The revision history of these specs is available [here](https://github.com/ruby/spec/blob/2b886623/CHANGES.before-2008-05-10).
These specs were later extracted to their own project, RubySpec, with a specific vision and principles.
At the end of 2014, Brian Shirai, the creator of RubySpec, decided to [end RubySpec](http://rubinius.com/2014/12/31/matz-s-ruby-developers-don-t-use-rubyspec/).
A couple months later, the different repositories were merged and [the project was revived](http://eregon.github.io/rubyspec/2015/07/29/rubyspec-is-reborn.html).
On 12 January 2016, the name was changed to "The Ruby Spec Suite" for clarity and to let the RubySpec ideology rest in peace.
