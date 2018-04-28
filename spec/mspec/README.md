[![Build Status](https://travis-ci.org/ruby/mspec.svg?branch=master)](https://travis-ci.org/ruby/mspec)

## Overview

MSpec is a specialized framework that is syntax-compatible with RSpec for
basic things like 'describe', 'it' blocks and 'before', 'after' actions. MSpec
contains additional features that assist in writing the RubySpecs used by
multiple Ruby implementations.

MSpec attempts to use the simplest Ruby language features so that beginning
Ruby implementations can run the Ruby specs.

MSpec is not intended as a replacement for RSpec. MSpec attempts to provide a
subset of RSpec's features in some cases and a superset in others. It does not
provide all the matchers, for instance.

However, MSpec provides several extensions to facilitate writing the Ruby
specs in a manner compatible with multiple Ruby implementations.

  1. MSpec offers a set of guards to control execution of the specs. These
     guards not only enable or disable execution but also annotate the specs
     with additional information about why they are run or not run.

  2. MSpec provides a different shared spec implementation specifically
     designed to ease writing specs for the numerous aliased methods in Ruby.
     The MSpec shared spec implementation should not conflict with RSpec's own
     shared behavior facility.

  3. MSpec provides various helper methods to simplify some specs, for
     example, creating temporary file names.

  4. MSpec has several specialized runner scripts that includes a
     configuration facility with a default project file and user-specific
     overrides.

## Requirements

MSpec requires Ruby 2.3 or more recent.

## Bundler

A Gemfile is provided. Use Bundler to install gem dependencies. To install
Bundler, run the following:

```bash
gem install bundler
```

To install the gem dependencies with Bundler, run the following:

```bash
ruby -S bundle install
```

## Running Specs

Use RSpec to run the MSpec specs. There are no plans currently to make the
MSpec specs runnable by MSpec.

After installing the gem dependencies, the specs can be run as follows:

```bash
ruby -S bundle exec rspec
```

Or

```bash
ruby -S rake
```

To run an individual spec file, use the following example:

```bash
ruby -S bundle exec rspec spec/helpers/ruby_exe_spec.rb
```


## Documentation

See http://ruby.github.io/rubyspec.github.io/


## Source Code

See https://github.com/ruby/mspec


## License

See the LICENSE in the source code.
