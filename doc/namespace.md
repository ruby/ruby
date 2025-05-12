# Namespace - Ruby's in-process separation of Classes and Modules

Namespace is designed to provide separated spaces in a Ruby process, to isolate applications and libraries.

## Known issues

* Experimental warning is shown when ruby starts with `RUBY_NAMESPACE=1` (specify `-W:no-experimental` option to hide it)
* `bundle install` may fail
* `require 'active_support'` may fail
* A wrong current namespace detection happens sometimes in the root namespace

## TODOs

* Identify the CI failure cause and restore temporarily skipped tests (mmtk, test/ruby/test_allocation on i686)
* Reconstruct current/loading namespace management based on control frames
* Add the loaded namespace on iseq to check if another namespace tries running the iseq (add a field only when VM_CHECK_MODE?)
* Delete per-namespace extension files (.so) lazily or process exit
* Collect rb_classext_t entries for a namespace when the namespace is collected
* Allocate an rb_namespace_t entry as the root namespace at first, then construct the contents and wrap it as rb_cNamespace instance later (to eliminate root/builtin two namespaces situation)
* Assign its own TOPLEVEL_BINDING in namespaces
* Fix `warn` in namespaces to refer `$VERBOSE` in the namespace
* Make an internal data container `Namespace::Entry` invisible
* More test cases about `$LOAD_PATH` and `$LOADED_FEATURES`
* Return classpath and nesting without the namespace prefix in the namespace itself [#21316](https://bugs.ruby-lang.org/issues/21316), [#21318](https://bugs.ruby-lang.org/issues/21318)

## How to use

### Enabling namespace

First, an environment variable should be set at the ruby process bootup: `RUBY_NAMESPACE=1`.
The only valid value is `1` to enable namespace. Other values (or unset `RUBY_NAMESPACE`) means disabling namespace. And setting the value after Ruby program starts doesn't work.

### Using namespace

`Namespace` class is the entrypoint of namespaces.

```ruby
ns = Namespace.new
ns.require('something') # or require_relative, load
```

The required file (either .rb or .so/.dll/.bundle) is loaded in the namespace (`ns` here). The required/loaded files from `something` will be loaded in the namespace recursively.

```ruby
# something.rb

X = 1

class Something
  def self.x = X
  def x = ::X
end
```

Classes/modules, those methods and constants defined in the namespace can be accessed via `ns` object.

```ruby
p ns::Something.x  # 1

X = 2
p X                # 2
p ::X              # 2
p ns::Something.x  # 1
p ns::X            # 1
```

Instance methods defined in the namespace also run with definitions in the namespace.

```ruby
s = ns::Something.new

p s.x  # 1
```

## Specifications

### Namespace types

There are two namespace types:

* Root namespace
* User namespace

There is the root namespace, just a single namespace in a Ruby process. Ruby bootstrap runs in the root namespace, and all builtin classes/modules are defined in the root namespace. (See "Builtin classes and modules".)

User namespaces are to run user-written programs and libraries loaded from user programs. The user's main program (specified by the `ruby` command line argument) is executed in the "main" namespace, which is a user namespace automatically created at the end of Ruby's bootstrap, copied from the root namespace.

When `Namespace.new` is called, an "optional" namespace (a user, non-main namespace) is created, copied from the root namespace. All user namespaces are flat, copied from the root namespace.

### Namespace class and instances

`Namespace` is a top level class, as a subclass of `Module`, and `Namespace` instances are a kind of `Module`.

### Classes and modules defined in namespace

The classes and modules, newly defined in a namespace `ns`, are defined under `ns`. For example, if a class `A` is defined in `ns`, it is actually defined as `ns::A`.

In the namespace `ns`, `ns::A` can be referred to as `A` (and `::A`). From outside of `ns`, it can be referred to as `ns::A`.

The main namespace is exceptional. Top level classes and modules defined in the main namespace are just top level classes and modules.

### Classes and modules reopened in namespace

In namespaces, builtin classes/modules are visible and can be reopened. Those classes/modules can be reopened using `class` or `module` clauses, and class/module definitions can be changed.

The changed definitions are visible only in the namespace. In other namespaces, builtin classes/modules and those instances work without changed definitions.

```ruby
# in foo.rb
class String
  BLANK_PATTERN = /\A\s*\z/
  def blank?
    self =~ BLANK_PATTERN
  end
end

module Foo
  def self.foo = "foo"

  def self.foo_is_blank?
    foo.blank?
  end
end

Foo.foo.blank? #=> false
"foo".blank?   #=> false

# in main.rb
ns = Namespace.new
ns.require('foo')

Foo.foo_is_blank? #=> false   (#blank? called in ns)

Foo.foo.blank?    # NoMethodError
"foo".blank?      # NoMethodError
String::BLANK_PATTERN # NameError
```

The main namespace and `ns` are different namespaces, so monkey patches in main are also invisible in `ns`.

### Builtin classes and modules

In the namespace context, "builtin" classes and modules are classes and modules:

* Accessible without any `require` calls in user scripts
* Defined before any user program start running
* Including classes/modules loaded by `prelude.rb` (including RubyGems `Gem`, for example)

Hereafter, "builtin classes and modules" will be referred to as just "builtin classes".

### Builtin classes referred via namespace objects

Builtin classes in a namespace `ns` can be referred from other namespace. For example, `ns::String` is a valid reference, and `String` and `ns::String` are identical (`String == ns::String`, `String.object_id == ns::String.object_id`).

`ns::String`-like reference returns just a `String` in the current namespace, so its definition is `String` in the namespace, not in `ns`.

```ruby
# foo.rb
class String
  def self.foo = "foo"
end

# main.rb
ns = Namespace.new
ns.require('foo')

ns::String.foo  # NoMethodError
```

### Class instance variables, class variables, constants

Builtin classes can have different sets of class instance variables, class variables and constants between namespaces.

```ruby
# foo.rb
class Array
  @v = "foo"
  @@v = "_foo_"
  V = "FOO"
end

Array.instance_variable_get(:@v) #=> "foo"
Array.class_variable_get(:@@v)   #=> "_foo_"
Array.const_get(:V)              #=> "FOO"

# main.rb
ns = Namespace.new
ns.require('foo')

Array.instance_variable_get(:@v) #=> nil
Array.class_variable_get(:@@v)   # NameError
Array.const_get(:V)              # NameError
```

### Global variables

In namespaces, changes on global variables are also isolated in the namespace. Changes on global variables in a namespace are visible/applied only in the namespace.

```ruby
# foo.rb
$foo = "foo"
$VERBOSE = nil

puts "This appears: '#{$foo}'"

# main.rb
p $foo      #=> nil
p $VERBOSE  #=> false

ns = Namespace.new
ns.require('foo')  # "This appears: 'foo'"

p $foo      #=> nil
p $VERBOSE  #=> false
```

### Top level constants

Usually, top level constants are defined as constants of `Object`. In namespaces, top level constants are constants of `Object` in the namespace. And the namespace object `ns`'s constants are strictly equal to constants of `Object`.

```ruby
# foo.rb
FOO = 100

FOO         #=> 100
Object::FOO #=> 100

# main.rb
ns = Namespace.new
ns.require('foo')

ns::FOO      #=> 100

FOO          # NameError
Object::FOO  # NameError
```

### Top level methods

Top level methods are private instance methods of `Object`, in each namespace.

```ruby
# foo.rb
def yay = "foo"

class Foo
  def self.say = yay
end

Foo.say #=> "foo"
yay     #=> "foo"

# main.rb
ns = Namespace.new
ns.require('foo')

ns.Foo.say  #=> "foo"

yay  # NoMethodError
```

There is no way to expose top level methods in namespaces to another namespace.
(See "Expose top level methods as a method of the namespace object" in "Discussions" section below)

### Namespace scopes

Namespace works in file scope. One `.rb` file runs in a single namespace.

Once a file is loaded in a namespace `ns`, all methods/procs defined/created in the file run in `ns`.

## Implementation details

#### Object Shapes

Once builtin classes are copied and modified in namespaces, its instance variable management fallbacks from Object Shapes to a traditional iv table (st_table) because RClass stores the shape in its `flags`, not in `rb_classext_t`.

#### Size of RClass and rb_classext_t

Namespace requires to move some fields from RClass to `rb_classext_t`, then the size of RClass and `rb_classext_t` is now larger than `4 * RVALUE_SIZE`. It's against the expectation of [Variable Width Allocation](https://rubykaigi.org/2021-takeout/presentations/peterzhu2118.html).

Now the `STATIC_ASSERT` to check the size is commented-out. (See "Minimize the size of RClass and rb_classext_t" in "Discussion" section below)

#### ISeq inline method/constant cache

As described above in "Namespace scopes", an ".rb" file runs in a namespace. So method/constant resolution will be done in a namespace consistently.

That means ISeq inline caches work well even with namespaces. Otherwise, it's a bug.

#### Method call global cache (gccct)

`rb_funcall()` C function refers to the global cc cache table (gccct), and the cache key is calculated with the current namespace.

So, `rb_funcall()` calls have a performance penalty when namespace is enabled.

#### Current namespace and loading namespace

The current namespace is the namespace that the executing code is in. `Namespace.current` returns the current namespace object.

The loading namespace is an internally managed namespace to determine the namespace to load newly required/loaded files. For example, `ns` is the loading namespace when `ns.require("foo")` is called.

## Discussions

#### Namespace#inspect

Currently, `Namespace#inspect` returns values like `"#<Namespace:0x00000001083a5660>"`. This results in the very redundant and poorly visible classpath outside the namespace.

```ruby
# foo.rb
class C; end

# main.rb
ns = Namespace.new
ns.require('foo')

p ns::C # "#<Namespace:0x00000001083a5660>::C"
```

And currently, if a namespace is assigned to a constant `NS1`, the classpath output will be `NS1::C`. But the namespace object can be brought to another namespace and the constant `NS1` in the namespace is something different. So the constant-based classpath for namespace is not safe basically.

So we should find a better format to show namespaces. Options are:

* `NS1::C` (only when this namespace is created and assigned to NS1 in the current namespace)
* `#<Namespace:user:1083a5660>::C` (with namespace type and without preceding 0)
* or something else

#### Namespace#eval

Testing namespace features needs to create files to be loaded in namespaces. It's not easy nor casual.

If `Namespace` class has an instance method `#eval` to evaluate code in the namespace, it can be helpful.

#### More builtin methods written in Ruby

If namespace is enabled by default, builtin methods can be written in Ruby because it can't be overridden by users' monkey patches. Builtin Ruby methods can be JIT-ed, and it could bring performance reward.

#### Monkey patching methods called by builtin methods

Builtin methods sometimes call other builtin methods. For example, `Hash#map` calls `Hash#each` to retrieve entries to be mapped. Without namespace, Ruby users can overwrite `Hash#each` and expect the behavior change of `Hash#map` as a result.

But with namespaces, `Hash#map` runs in the root namespace. Ruby users can define `Hash#each` only in user namespaces, so users cannot change `Hash#map`'s behavior in this case. To achieve it, users should override both`Hash#map` and `Hash#each` (or only `Hash#map`).

It is a breaking change.

It's an option to change the behavior of methods in the root namespace to refer to definitions in user namespaces. But if we do so, that means we can't proceed with "More builtin methods written in Ruby".

#### Context of \$LOAD\_PATH and \$LOADED\_FEATURES

Global variables `$LOAD_PATH` and `$LOADED_FEATURES` control `require` method behaviors. So those namespaces are determined by the loading namespace instead of the current namespace.

This could potentially conflict with the user's expectations. We should find the solution.

#### Expose top level methods as a method of the namespace object

Currently, top level methods in namespaces are not accessible from outside of the namespace. But there might be a use case to call other namespace's top level methods.

#### Split root and builtin namespace

NOTE: "builtin" namespace is a different one from the "builtin" namespace in the current implementation

Currently, the single "root" namespace is the source of classext CoW. And also, the "root" namespace can load additional files after starting main script evaluation by calling methods which contain lines like `require "openssl"`.

That means, user namespaces can have different sets of definitions according to when it is created.

```
[root]
 |
 |----[main]
 |
 |(require "openssl" called in root)
 |
 |----[ns1] having OpenSSL
 |
 |(remove_const called for OpenSSL in root)
 |
 |----[ns2] without OpenSSL
```

This could cause unexpected behavior differences between user namespaces. It should NOT be a problem because user scripts which refer to `OpenSSL` should call `require "openssl"` by themselves.
But in the worst case, a script (without `require "openssl"`) runs well in `ns1`, but doesn't run in `ns2`. This situation looks like a "random failure" to users.

An option possible to prevent this situation is to have "root" and "builtin" namespaces.

* root
  * The namespace for the Ruby process bootstrap, then the source of CoW
  * After starting the main namespace, no code runs in this namespace
* builtin
  * The namespace copied from the root namespace at the same time with "main"
  * Methods and procs defined in the "root" namespace run in this namespace
  * Classes and modules required will be loaded in this namespace

This design realizes a consistent source of namespace CoW.

#### Separate cc_tbl and callable_m_tbl, cvc_tbl for less classext CoW

The fields of `rb_classext_t` contains several cache(-like) data, `cc_tbl`(callcache table), `callable_m_tbl`(table of resolved complemented methods) and `cvc_tbl`(class variable cache table).

The classext CoW is triggered when the contents of `rb_classext_t` are changed, including `cc_tbl`, `callable_m_tbl`, and `cvc_tbl`. But those three tables are changed by just calling methods or referring class variables. So, currently, classext CoW is triggered much more times than the original expectation.

If we can move those three tables outside of `rb_classext_t`, the number of copied `rb_classext_t` will be much less than the current implementation.

#### Object Shapes per namespace

Now the classext CoW requires RClass and `rb_classext_t` to fallback its instance variable management from Object Shapes to the traditional `st_table`. It may have a performance penalty.

If we can apply Object Shapes on `rb_classext_t` instead of `RClass`, per-namespace classext can have its own shapes, and it may be able to avoid the performance penalty.

#### Minimize the size of RClass and rb_classext_t

As described in "Size of RClass and rb_classext_t" section above, the size of RClass and `rb_classext_t` is currently larger than `4 * RVALUE_SIZE` (`20 * VALUE_SIZE`). Now the size is `23 * VALUE_SIZE + 7 bits`.

The fields possibly removed from `rb_classext_t` are:

* `cc_tbl`, `callable_m_tbl`, `cvc_tbl` (See the section "Separate cc_tbl and callable_m_tbl, cvc_tbl for less classext CoW" above)
* `ns_super_subclasses`, `module_super_subclasses`
  * `RCLASSEXT_SUBCLASSES(RCLASS_EXT_PRIME(RCLASSEXT_SUPER(klass)))->ns_subclasses` can replace it
  * These fields are used only in GC, how's the actual performance benefit?

If we can move or remove those fields, the size satisfies the assertion (`<= 4 * RVALUE_SIZE`).
