Contributions are much appreciated.
Please open a pull request or add an issue to discuss what you intend to work on.
If the pull requests passes the CI and conforms to the existing style of specs, it will be merged.

### File organization

Spec are grouped in 5 separate top-level groups:

* `command_line`: for the ruby executable command-line flags (`-v`, `-e`, etc)
* `language`: for the language keywords and syntax constructs (`if`, `def`, `A::B`, etc)
* `core`: for the core methods (`Integer#+`, `String#upcase`, no need to require anything)
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

#### Comparison matchers

```ruby
(1 + 2).should == 3 # Calls #==
(1 + 2).should_not == 5

File.should.equal?(File) # Calls #equal? (tests identity)
(1 + 2).should.eql?(3) # Calls #eql? (Hash equality)

1.should < 2
2.should <= 2
3.should >= 3
4.should > 3

"Hello".should =~ /l{2}/ # Calls #=~ (Regexp match)
```

#### Predicate matchers

```ruby
[].should.empty?
[1,2,3].should.include?(2)

"hello".should.start_with?("h")
"hello".should.end_with?("o")

(0.1 + 0.2).should be_close(0.3, TOLERANCE) # (0.2-0.1).abs < TOLERANCE
(0.0/0.0).should.nan?
(1.0/0.0).should be_positive_infinity
(-1.0/0.0).should be_negative_infinity

3.14.should be_an_instance_of(Float) # Calls #instance_of?
3.14.should be_kind_of(Numeric) # Calls #is_a?
Numeric.should be_ancestor_of(Float) # Float.ancestors.include?(Numeric)

3.14.should.respond_to?(:to_i)
Integer.should have_instance_method(:+)
Array.should have_method(:new)
```

Also `have_constant`, `have_private_instance_method`, `have_singleton_method`, etc.

#### Exception matchers

```ruby
-> {
  raise "oops"
}.should raise_error(RuntimeError, /oops/)

-> {
  raise "oops"
}.should raise_error(RuntimeError) { |e|
  # Custom checks on the Exception object
  e.message.should.include?("oops")
  e.cause.should == nil
}
```

##### should_not raise_error

**To avoid!** Instead, use an expectation testing what the code in the lambda does.
If an exception is raised, it will fail the example anyway.

```ruby
-> { ... }.should_not raise_error
```

#### Warning matcher

```ruby
-> {
  Fixnum
}.should complain(/constant ::Fixnum is deprecated/) # Expect a warning
```

### Guards

Different guards are available as defined by mspec.
Here is a list of the most commonly-used guards:

#### Version guards

```ruby
ruby_version_is ""..."2.6" do
  # Specs for RUBY_VERSION < 2.6
end

ruby_version_is "2.6" do
  # Specs for RUBY_VERSION >= 2.6
end
```

#### Platform guards

```ruby
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
```

#### Guard for bug

In case there is a bug in MRI and the fix will be backported to previous versions.
If it is not backported or not likely, use `ruby_version_is` instead.
First, file a bug at https://bugs.ruby-lang.org/.
The problem is `ruby_bug` would make non-MRI implementations fail this spec while MRI itself does not pass it, so it should only be used if the bug is/will be fixed and backported.

```ruby
ruby_bug '#13669', ''...'3.2' do
  it "works like this" do
    # Specify the expected behavior here, not the bug
  end
end
```

#### Combining guards

```ruby
guard -> { platform_is :windows and ruby_version_is ""..."2.6" } do
  # Windows and RUBY_VERSION < 2.6
end

guard_not -> { platform_is :windows and ruby_version_is ""..."2.6" } do
  # The opposite
end
```

#### Custom guard

```ruby
max_uint = (1 << 32) - 1
guard -> { max_uint <= fixnum_max } do
end
```

Custom guards are better than a simple `if` as they allow [mspec commands](https://github.com/ruby/mspec/issues/30#issuecomment-312487779) to work properly.

#### Implementation-specific behaviors

In general, the usage of guards should be minimized as possible.

There are no guards to define implementation-specific behavior because
the Ruby Spec Suite defines common behavior and not implementation details.
Use the implementation test suite for these.

If an implementation does not support some feature, simply tag the related specs as failing instead.

### Shared Specs

Often throughout Ruby, identical functionality is used by different methods and modules. In order
to avoid duplication of specs, we have shared specs that are re-used in other specs. The use is a
bit tricky however, so let's go over it.

Commonly, if a shared spec is only reused within its own module, the shared spec will live within a
shared directory inside that module's directory. For example, the `core/hash/shared/key.rb` spec is
only used by `Hash` specs, and so it lives inside `core/hash/shared/`.

When a shared spec is used across multiple modules or classes, it lives within the `shared/` directory.
An example of this is the `shared/file/socket.rb` which is used by `core/file/socket_spec.rb`,
`core/filetest/socket_spec.rb`, and `core/file/state/socket_spec.rb` and so it lives in the root `shared/`.

Defining a shared spec involves adding a `shared: true` option to the top-level `describe` block. This
will signal not to run the specs directly by the runner. Shared specs have access to two instance
variables from the implementor spec: `@method` and `@object`, which the implementor spec will pass in.

Here's an example of a snippet of a shared spec and two specs which integrates it:

```ruby
# core/hash/shared/key.rb
describe :hash_key_p, shared: true do
  it "returns true if the key's matching value was false" do
    { xyz: false }.send(@method, :xyz).should == true
  end
end

# core/hash/key_spec.rb
describe "Hash#key?" do
  it_behaves_like :hash_key_p, :key?
end

# core/hash/include_spec.rb
describe "Hash#include?" do
  it_behaves_like :hash_key_p, :include?
end
```

In the example, the first `describe` defines the shared spec `:hash_key_p`, which defines a spec that
calls the `@method` method with an expectation. In the implementor spec, we use `it_behaves_like` to
integrate the shared spec. `it_behaves_like` takes 3 parameters: the key of the shared spec, a method,
and an object. These last two parameters are accessible via `@method` and `@object` in the shared spec.

Sometimes, shared specs require more context from the implementor class than a simple object. We can address
this by passing a lambda as the method, which will have the scope of the implementor. Here's an example of
how this is used currently:

```ruby
describe :kernel_sprintf, shared: true do
  it "raises TypeError exception if cannot convert to Integer" do
    -> { @method.call("%b", Object.new) }.should raise_error(TypeError)
  end
end

describe "Kernel#sprintf" do
  it_behaves_like :kernel_sprintf, -> (format, *args) {
    sprintf(format, *args)
  }
end

describe "Kernel.sprintf" do
  it_behaves_like :kernel_sprintf, -> (format, *args) {
    Kernel.sprintf(format, *args)
  }
end
```

In the above example, the method being passed is a lambda that triggers the specific conditions of the shared spec.

### Style

Do not leave any trailing space and follow the existing style.
