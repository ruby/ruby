# spec/bundler

spec/bundler is rspec examples for bundler library (`lib/bundler.rb`, `lib/bundler/*`).

## Running spec/bundler

To run rspec for bundler:

```bash
make test-bundler
```

or run rspec with parallel execution:

```bash
make test-bundler-parallel
```

If you specify `BUNDLER_SPECS=foo/bar_spec.rb` then only `spec/bundler/foo/bar_spec.rb` will be run.

# spec/ruby

ruby/spec (https://github.com/ruby/spec/) is
a test suite for the Ruby language.

Once a month, @eregon merges the in-tree copy under spec/ruby
with the upstream repository, preserving the commits and history.
The same happens for other implementations such as JRuby and TruffleRuby.

Feel welcome to modify the in-tree spec/ruby.
This is the purpose of the in-tree copy,
to facilitate contributions to ruby/spec for MRI developers.

New features, additional tests for existing features and
regressions tests are all welcome in ruby/spec.
There is very little behavior that is implementation-specific,
as in the end user programs tend to rely on every behavior MRI exhibits.
In other words: If adding a spec might reveal a bug in
another implementation, then it is worth adding it.
Currently, the only module which is MRI-specific is `RubyVM`.

## Changing behavior and versions guards

Version guards (`ruby_version_is`) must be added for new features or features
which change behavior or are removed. This is necessary for other Ruby implementations
to still be able to run the specs and contribute new specs.

For example, change:

```ruby
describe "Some spec" do
  it "some example" do
    # Old behavior for Ruby < 2.7
  end
end
```

to:

```ruby
describe "Some spec" do
  ruby_version_is ""..."2.7" do
    it "some example" do
      # Old behavior for Ruby < 2.7
    end
  end

  ruby_version_is "2.7" do
    it "some example" do
      # New behavior for Ruby >= 2.7
    end
  end
end
```

See `spec/ruby/CONTRIBUTING.md` for more documentation about guards.

To verify specs are compatible with older Ruby versions:

```bash
cd spec/ruby
$RUBY_MANAGER use 2.4.9
../mspec/bin/mspec -j
```

## Running ruby/spec

To run all specs:

```bash
make test-spec
```

Extra arguments can be added via `MSPECOPT`.
For instance, to show the help:

```bash
make test-spec MSPECOPT=-h
```

You can also run the specs in parallel, which is currently experimental.
It takes around 10s instead of 60s on a quad-core laptop.

```bash
make test-spec MSPECOPT=-j
```

To run a specific test, add its path to the command:

```bash
make test-spec MSPECOPT=spec/ruby/language/for_spec.rb
```

If ruby trunk is your current `ruby` in `$PATH`, you can also run `mspec` directly:

```bash
# change ruby to trunk
ruby -v # => trunk
spec/mspec/bin/mspec spec/ruby/language/for_spec.rb
```

## ruby/spec and test/

The main difference between a "spec" under `spec/ruby/` and
a test under `test/` is that specs are documenting what they test.
This is extremely valuable when reading these tests, as it
helps to quickly understand what specific behavior is tested,
and how a method should behave. Basic English is fine for spec descriptions.
Specs also tend to have few expectations (assertions) per spec,
as they specify one aspect of the behavior and not everything at once.
Beyond that, the syntax is slightly different but it does the same thing:
`assert_equal 3, 1+2` is just `(1+2).should == 3`.

Example:

```ruby
describe "The for expression" do
  it "iterates over an Enumerable passing each element to the block" do
    j = 0
    for i in 1..3
      j += i
    end
    j.should == 6
  end
end
```

For more details, see `spec/ruby/CONTRIBUTING.md`.

# spec/syntax_suggest

## Running spec/syntax_suggest

To run rspec for syntax_suggest:

```bash
make test-syntax-suggest
```

If you specify `SYNTAX_SUGGEST_SPECS=foo/bar_spec.rb` then only `spec/syntax_suggest/foo/bar_spec.rb` will be run.
