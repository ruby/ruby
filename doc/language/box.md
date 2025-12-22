# Ruby Box - Ruby's in-process separation of Classes and Modules

Ruby Box is designed to provide separated spaces in a Ruby process, to isolate application codes, libraries and monkey patches.

## Known issues

* Experimental warning is shown when ruby starts with `RUBY_BOX=1` (specify `-W:no-experimental` option to hide it)
* Installing native extensions may fail under `RUBY_BOX=1` because of stack level too deep in extconf.rb
* `require 'active_support/core_ext'` may fail under `RUBY_BOX=1`
* Defined methods in a box may not be referred by built-in methods written in Ruby

## TODOs

* Add the loaded box on iseq to check if another box tries running the iseq (add a field only when VM_CHECK_MODE?)
* Assign its own TOPLEVEL_BINDING in boxes
* Fix calling `warn` in boxes to refer `$VERBOSE` and `Warning.warn` in the box
* Make an internal data container class `Ruby::Box::Entry` invisible
* More test cases about `$LOAD_PATH` and `$LOADED_FEATURES`

## How to use

### Enabling Ruby Box

First, an environment variable should be set at the ruby process bootup: `RUBY_BOX=1`.
The only valid value is `1` to enable Ruby Box. Other values (or unset `RUBY_BOX`) means disabling Ruby Box. And setting the value after Ruby program starts doesn't work.

### Using Ruby Box

`Ruby::Box` class is the entrypoint of Ruby Box.

```ruby
box = Ruby::Box.new
box.require('something') # or require_relative, load
```

The required file (either .rb or .so/.dll/.bundle) is loaded in the box (`box` here). The required/loaded files from `something` will be loaded in the box recursively.

```ruby
# something.rb

X = 1

class Something
  def self.x = X
  def x = ::X
end
```

Classes/modules, those methods and constants defined in the box can be accessed via `box` object.

```ruby
X = 2
p X                 # 2
p ::X               # 2
p box::Something.x  # 1
p box::X            # 1
```

Instance methods defined in the box also run with definitions in the box.

```ruby
s = box::Something.new

p s.x  # 1
```

## Specifications

### Ruby Box types

There are two box types:

* Root box
* User boxes

There is the root box, just a single box in a Ruby process. Ruby bootstrap runs in the root box, and all builtin classes/modules are defined in the root box. (See "Builtin classes and modules".)

User boxes are to run user-written programs and libraries loaded from user programs. The user's main program (specified by the `ruby` command line argument) is executed in the "main" box, which is a user box automatically created at the end of Ruby's bootstrap, copied from the root box.

When `Ruby::Box.new` is called, an "optional" box (a user, non-main box) is created, copied from the root box. All user boxes are flat, copied from the root box.

### Ruby Box class and instances

`Ruby::Box` is a class, as a subclass of `Module`. `Ruby::Box` instances are a kind of `Module`.

### Classes and modules defined in boxes

The classes and modules, newly defined in a box `box`, are accessible via `box`. For example, if a class `A` is defined in `box`, it is accessible as `box::A` from outside of the box.

In the box `box`, `A` can be referred to as `A` (and `::A`).

### Built-in classes and modules reopened in boxes

In boxes, builtin classes/modules are visible and can be reopened. Those classes/modules can be reopened using `class` or `module` clauses, and class/module definitions can be changed.

The changed definitions are visible only in the box. In other boxes, builtin classes/modules and those instances work without changed definitions.

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
box = Ruby::Box.new
box.require('foo')

box::Foo.foo_is_blank? #=> false   (#blank? called in box)

"foo".blank?          # NoMethodError
String::BLANK_PATTERN # NameError
```

The main box and `box` are different boxes, so monkey patches in main are also invisible in `box`.

### Builtin classes and modules

In the box context, "builtin" classes and modules are classes and modules:

* Accessible without any `require` calls in user scripts
* Defined before any user program start running
* Including classes/modules loaded by `prelude.rb` (including RubyGems `Gem`, for example)

Hereafter, "builtin classes and modules" will be referred to as just "builtin classes".

### Builtin classes referred via box objects

Builtin classes in a box `box` can be referred from other boxes. For example, `box::String` is a valid reference, and `String` and `box::String` are identical (`String == box::String`, `String.object_id == box::String.object_id`).

`box::String`-like reference returns just a `String` in the current box, so its definition is `String` in the box, not in `box`.

```ruby
# foo.rb
class String
  def self.foo = "foo"
end

# main.rb
box = Ruby::Box.new
box.require('foo')

box::String.foo  # NoMethodError
```

### Class instance variables, class variables, constants

Builtin classes can have different sets of class instance variables, class variables and constants between boxes.

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
box = Ruby::Box.new
box.require('foo')

Array.instance_variable_get(:@v) #=> nil
Array.class_variable_get(:@@v)   # NameError
Array.const_get(:V)              # NameError
```

### Global variables

In boxes, changes on global variables are also isolated in the boxes. Changes on global variables in a box are visible/applied only in the box.

```ruby
# foo.rb
$foo = "foo"
$VERBOSE = nil

puts "This appears: '#{$foo}'"

# main.rb
p $foo      #=> nil
p $VERBOSE  #=> false

box = Ruby::Box.new
box.require('foo')  # "This appears: 'foo'"

p $foo      #=> nil
p $VERBOSE  #=> false
```

### Top level constants

Usually, top level constants are defined as constants of `Object`. In boxes, top level constants are constants of `Object` in the box. And the box object `box`'s constants are strictly equal to constants of `Object`.

```ruby
# foo.rb
FOO = 100

FOO         #=> 100
Object::FOO #=> 100

# main.rb
box = Ruby::Box.new
box.require('foo')

box::FOO      #=> 100

FOO          # NameError
Object::FOO  # NameError
```

### Top level methods

Top level methods are private instance methods of `Object`, in each box.

```ruby
# foo.rb
def yay = "foo"

class Foo
  def self.say = yay
end

Foo.say #=> "foo"
yay     #=> "foo"

# main.rb
box = Ruby::Box.new
box.require('foo')

box::Foo.say  #=> "foo"

yay  # NoMethodError
```

There is no way to expose top level methods in boxes to others.
(See "Expose top level methods as a method of the box object" in "Discussions" section below)

### Ruby Box scopes

Ruby Box works in file scope. One `.rb` file runs in a single box.

Once a file is loaded in a box `box`, all methods/procs defined/created in the file run in `box`.

### Utility methods

Several methods are available for trying/testing Ruby Box.

* `Ruby::Box.current` returns the current box
* `Ruby::Box.enabled?` returns true/false to represent `RUBY_BOX=1` is specified or not
* `Ruby::Box.root` returns the root box
* `Ruby::Box.main` returns the main box
* `Ruby::Box#eval` evaluates a Ruby code (String) in the receiver box, just like calling `#load` with a file

## Implementation details

#### ISeq inline method/constant cache

As described above in "Ruby Box scopes", an ".rb" file runs in a box. So method/constant resolution will be done in a box consistently.

That means ISeq inline caches work well even with boxes. Otherwise, it's a bug.

#### Method call global cache (gccct)

`rb_funcall()` C function refers to the global cc cache table (gccct), and the cache key is calculated with the current box.

So, `rb_funcall()` calls have a performance penalty when Ruby Box is enabled.

#### Current box and loading box

The current box is the box that the executing code is in. `Ruby::Box.current` returns the current box object.

The loading box is an internally managed box to determine the box to load newly required/loaded files. For example, `box` is the loading box when `box.require("foo")` is called.

## Discussions

#### More builtin methods written in Ruby

If Ruby Box is enabled by default, builtin methods can be written in Ruby because it can't be overridden by users' monkey patches. Builtin Ruby methods can be JIT-ed, and it could bring performance reward.

#### Monkey patching methods called by builtin methods

Builtin methods sometimes call other builtin methods. For example, `Hash#map` calls `Hash#each` to retrieve entries to be mapped. Without Ruby Box, Ruby users can overwrite `Hash#each` and expect the behavior change of `Hash#map` as a result.

But with boxes, `Hash#map` runs in the root box. Ruby users can define `Hash#each` only in user boxes, so users cannot change `Hash#map`'s behavior in this case. To achieve it, users should override both`Hash#map` and `Hash#each` (or only `Hash#map`).

It is a breaking change.

Users can define methods using `Ruby::Box.root.eval(...)`, but it's clearly not ideal API.

#### Assigning values to global variables used by builtin methods

Similar to monkey patching methods, global variables assigned in a box is separated from the root box. Methods defined in the root box referring a global variable can't find the re-assigned one.

#### Context of `$LOAD_PATH` and `$LOADED_FEATURES`

Global variables `$LOAD_PATH` and `$LOADED_FEATURES` control `require` method behaviors. So those variables are determined by the loading box instead of the current box.

This could potentially conflict with the user's expectations. We should find the solution.

#### Expose top level methods as a method of the box object

Currently, top level methods in boxes are not accessible from outside of the box. But there might be a use case to call other box's top level methods.

#### Split root and builtin box

Currently, the single "root" box is the source of classext CoW. And also, the "root" box can load additional files after starting main script evaluation by calling methods which contain lines like `require "openssl"`.

That means, user boxes can have different sets of definitions according to when it is created.

```
[root]
 |
 |----[main]
 |
 |(require "openssl" called in root)
 |
 |----[box1] having OpenSSL
 |
 |(remove_const called for OpenSSL in root)
 |
 |----[box2] without OpenSSL
```

This could cause unexpected behavior differences between user boxes. It should NOT be a problem because user scripts which refer to `OpenSSL` should call `require "openssl"` by themselves.
But in the worst case, a script (without `require "openssl"`) runs well in `box1`, but doesn't run in `box2`. This situation looks like a "random failure" to users.

An option possible to prevent this situation is to have "root" and "builtin" boxes.

* root
  * The box for the Ruby process bootstrap, then the source of CoW
  * After starting the main box, no code runs in this box
* builtin
  * The box copied from the root box at the same time with "main"
  * Methods and procs defined in the "root" box run in this box
  * Classes and modules required will be loaded in this box

This design realizes a consistent source of box CoW.

#### Separate `cc_tbl` and `callable_m_tbl`, `cvc_tbl` for less classext CoW

The fields of `rb_classext_t` contains several cache(-like) data, `cc_tbl`(callcache table), `callable_m_tbl`(table of resolved complemented methods) and `cvc_tbl`(class variable cache table).

The classext CoW is triggered when the contents of `rb_classext_t` are changed, including `cc_tbl`, `callable_m_tbl`, and `cvc_tbl`. But those three tables are changed by just calling methods or referring class variables. So, currently, classext CoW is triggered much more times than the original expectation.

If we can move those three tables outside of `rb_classext_t`, the number of copied `rb_classext_t` will be much less than the current implementation.
