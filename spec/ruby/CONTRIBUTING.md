Contributions are much appreciated.
Please open a pull request or add an issue to discuss what you intend to work on.
If the pull requests passes the CI and conforms to the existing style of specs, it will be merged.

### File organization

Spec are grouped in 5 separate top-level groups:

* `command_line`: for the ruby executable command-line flags (`-v`, `-e`, etc)
* `language`: for the language keywords and syntax constructs (`if`, `def`, `A::B`, etc)
* `core`: for the core methods (`Fixnum#+`, `String#upcase`, no need to require anything)
* `library`: for the standard libraries methods (`CSV.new`, `YAML.parse`, need to require the stdlib)
* `optional/capi`: for functions available to the Ruby C-extension API

The exact file for methods is decided by the `#owner` of a method, for instance for `#group_by`:
```ruby
> [].method(:group_by)
=> #<Method: Array(Enumerable)#group_by>
> [].method(:group_by).owner
=> Enumerable
```
Which should therefore be specified in `core/enumerable/group_by_spec.rb`.

### MkSpec - a tool to generate the spec structure

If you want to create new specs, you should use `mkspec`, part of [MSpec](http://github.com/ruby/mspec).

    $ ../mspec/bin/mkspec -h

#### Creating files for unspecified modules or classes

For instance, to create specs for `forwardable`:

    $ ../mspec/bin/mkspec -b library -rforwardable -c Forwardable

Specify `core` or `library` as the `base`.

#### Finding unspecified core methods

This is very easy, just run the command below in your `spec` directory.
`ruby` must be a recent version of MRI.

    $ ruby --disable-gem ../mspec/bin/mkspec

You might also want to search for:

    it "needs to be reviewed for spec completeness"

which indicates the file was generated but the method unspecified.

### Matchers and expectations

Here is a list of frequently-used matchers, which should be enough for most specs.
There are a few extra specific matchers used in the couple specs that need it.

```ruby
(1 + 2).should == 3 # Calls #==
(1 + 2).should_not == 5

File.should equal(File) # Calls #equal? (tests identity)
(1 + 2).should eql(3) # Calls #eql? (Hash equality)

1.should < 2
2.should <= 2
3.should >= 3
4.should > 3

"Hello".should =~ /l{2}/ # Calls #=~ (Regexp match)

[].should be_empty # Calls #empty?
[1,2,3].should include(2) # Calls #include?

(0.1 + 0.2).should be_close(0.3, TOLERANCE) # (0.2-0.1).abs < TOLERANCE
(0.0/0.0).should be_nan # Calls Float#nan?
(1.0/0.0).should be_positive_infinity
(-1.0/0.0).should be_negative_infinity

3.14.should be_an_instance_of(Float) # Calls #instance_of?
3.14.should be_kind_of(Numeric) # Calls #is_a?
Numeric.should be_ancestor_of(Float) # Float.ancestors.include?(Numeric)

3.14.should respond_to(:to_i) # Calls #respond_to?
Fixnum.should have_instance_method(:+)
Array.should have_method(:new)
# Also have_constant, have_private_instance_method, have_singleton_method, etc

-> {
  raise "oops"
}.should raise_error(RuntimeError, /oops/)

# To avoid! Instead, use an expectation testing what the code in the lambda does.
# If an exception is raised, it will fail the example anyway.
-> { ... }.should_not raise_error

-> {
  Fixnum
}.should complain(/constant ::Fixnum is deprecated/) # Expect a warning
```

### Guards

Different guards are available as defined by mspec.
Here is a list of the most commonly-used guards:

```ruby
ruby_version_is ""..."2.4" do
  # Specs for RUBY_VERSION < 2.4
end

ruby_version_is "2.4" do
  # Specs for RUBY_VERSION >= 2.4
end

platform_is :windows do
  # Specs only valid on Windows
end

platform_is_not :windows do
  # Specs valid on platforms other than Windows
end

platform_is :linux, :darwin do # OR
end

platform_is_not :linux, :darwin do # Not Linux and not Darwin
end

platform_is wordsize: 64 do
  # 64-bit platform
end

big_endian do
  # Big-endian platform
end

# In case there is a bug in MRI but the expected behavior is obvious
# First file a bug at https://bugs.ruby-lang.org/
# It is better to use a ruby_version_is guard if there was a release with the fix
ruby_bug '#13669', ''...'2.5' do
  it "works like this" do
    # Specify the expected behavior here, not the bug
  end
end


# Combining guards
guard -> { platform_is :windows and ruby_version_is ""..."2.3" } do
  # Windows and RUBY_VERSION < 2.3
end

guard_not -> { platform_is :windows and ruby_version_is ""..."2.3" } do
  # The opposite
end

# Custom guard
max_uint = (1 << 32) - 1
guard -> { max_uint <= fixnum_max } do
end
```

In general, the usage of guards should be minimized as possible.

There are no guards to define implementation-specific behavior because
the Ruby Spec Suite defines common behavior and not implementation details.
Use the implementation test suite for these.

If an implementation does not support some feature, simply tag the related specs as failing instead.

### Style

Do not leave any trailing space and respect the existing style.
