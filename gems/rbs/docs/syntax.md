# Syntax

## Types

```markdown
_type_ ::= _class-name_ _type-arguments_                (Class instance type)
         | _interface-name_ _type-arguments_            (Interface type)
         | `singleton(` _class-name_ `)`                (Class singleton type)
         | _alias-name_                                 (Alias type)
         | _literal_                                    (Literal type)
         | _type_ `|` _type_                            (Union type)
         | _type_ `&` _type_                            (Intersection type)
         | _type_ `?`                                   (Optional type)
         | `{` _record-name_ `:` _type_ `,` ... `}`     (Record type)
         | `[]` | `[` _type_ `,` ... `]`                (Tuples)
         | _type-variable_                              (Type variables)
         | `^(` _parameters_ `) ->` _type_              (Proc type)
         | `self`
         | `instance`
         | `class`
         | `bool`
         | `untyped`
         | `nil`
         | `top`
         | `bot`
         | `void`

_class-name_ ::= _namespace_ /[A-Z]\w*/
_interface-name_ ::= _namespace_ /_[A-Z]\w*/
_alias-name_ ::= _namespace_ /[a-z]\w*/

_type-variable_ ::= /[A-Z]\w*/

_namespace_ ::=                                         (Empty namespace)
              | `::`                                    (Root)
              | _namespace_ /[A-Z]\w*/ `::`             (Namespace)

_type-arguments_ ::=                                    (No application)
                   | `[` _type_ `,` ... `]`             (Type application)

_literal_ ::= _string-literal_
            | _symbol-literal_
            | _integer-literal_
            | `true`
            | `false`
```

### Class instance type

Class instance type denotes _an instance of a class_.

```
Integer                      # Instance of Integer class
::Integer                    # Instance of ::Integer class
Hash[Symbol, String]         # Instance of Hash class with type application of Symbol and String
```

### Interface type

Interface type denotes _type of a value which can be a subtype of the interface_.

```
_ToS                          # _ToS interface
::MyApp::_Each[String]        # Interface name with namespace and type application
```

### Class singleton type

Class singleton type denotes _the type of a singleton object of a class_.

```
singleton(String)
singleton(::Hash)            # Class singleton type cannot be parametrized.
```

### Alias type

Alias type denotes an alias declared with _alias declaration_.

The name of type aliases starts with lowercase `[a-z]`.


```
name
::JSON::t                    # Alias name with namespace
```

### Literal type

Literal type denotes _a type with only one value of the literal_.

```
123                         # Integer
"hello world"               # A string
:to_s                       # A symbol
true                        # true or false
```

### Union type

Union type denotes _a type of one of the given types_.

```
Integer | String           # Integer or String
Array[Integer | String]    # Array of Integer or String
```

### Intersection type

Intersection type denotes _a type of all of the given types_.

```
Integer & String           # Integer and String
```

Note that `&` has higher precedence than `|` that `Integer & String | Symbol` is `(Integer & String) | Symbol`.

### Optional type

Optional type denotes _a type of value or nil_.

```
Integer?
Array[Integer?]
```

### Record type

Records are `Hash` objects, fixed set of keys, and heterogeneous.

```
{ id: Integer, name: String }     # Hash object like `{ id: 31, name: String }`
```

### Tuple type

Tuples are `Array` objects, fixed size and heterogeneous.

```
[ ]                               # Empty like `[]`
[String]                          # Single string like `["hi"]`
[Integer, Integer]                # Pair of integers like `[1, 2]`
[Symbol, Integer, Integer]        # Tuple of Symbol, Integer, and Integer like `[:pair, 30, 22]`
```

*Empty tuple* or *1-tuple* sound strange, but RBS allows these types.

### Type variable

```
U
T
S
Elem
```

Type variables cannot be distinguished from _class instance types_.
They are scoped in _class/module/interface declaration_ or _generic method types_.

```
class Ref[T]              # Object is scoped in the class declaration.
  @value: T               # Type variable `T`
  def map: [X] { (T) -> X } -> Ref[X]   # X is a type variable scoped in the method type.
end
```

### Proc type

Proc type denots type of procedures, `Proc` instances.

```
^(Integer) -> String                  # A procedure with an `Integer` parameter and returns `String`
^(?String, size: Integer) -> bool     # A procedure with `String` optional parameter, `size` keyword of `Integer`, and returns `bool`
```

### Base types

`self` denotes the type of receiver. The type is used to model the open recursion via `self`.

`instance` denotes the type of instance of the class. `class` is the singleton of the class.

`bool` is an abstract type for truth value.

`untyped` is for _a type without type checking_. It is `?` in gradual typing, _dynamic_ in some languages like C#, and _any_ in TypeScript. It is both subtype _and_ supertype of all of the types. (The type was `any` but renamed to `untyped`.)

`nil` is for _nil_.

`top` is a supertype of all of the types. `bot` is a subtype of all of the types.

`void` is a supertype of all of the types.

#### `nil` or `NilClass`?

We recommend using `nil`.

#### `bool` or `TrueClass | FalseClass`

We recommend using `bool` because it is more close to Ruby's semantics. If the type of a parameter of a method is `bool`, we usually pass `true` and `false`, and also `nil` or any other values. `TrueClass | FalseClass` rejects other values than `true` and `false`.

#### `void`, `bool`, or `top`?

They are all equivalent for the type system; they are all _top type_.

`void` tells developers a hint that _the value should not be used_. `bool` implies the value is used as a truth value. `top` is anything else.

## Method Types

```markdown
_method-type_ ::= `(` _parameters_ `) ->` _type_                                       # Method without block
                | `(` _parameters_ `) { (` _parameters_ `) -> ` _type_ `} ->` _type_   # Method with required block
                | `(` _parameters_ `) ?{ (` _parameters_ `) -> ` _type_ `} ->` _type_  # Method with optional block

_parameters_ ::= _required-positionals_ _optional-positionals_ _rest-positional_ _trailing-positionals_ _keywords_

_paramater_ ::= _type_ _var-name_                                  # Parameter with var name
              | _type_                                             # Parameter without var name
_required-positionals_ ::= _parameter_ `,` ...
_optional-positionals_ ::= `?` _parameter_ `,` ...
_rest-positional_ ::=                                              # Empty
                    | `*` _parameter_
_trailing-positionals_ ::= _parameter_ `,` ...
_keywords_ ::=                                                     # Empty
             | `**` _parameter_                                    # Rest keyword
             | _keyword_ `:` _parameter_ `,` _keywords_            # Required keyword
             | `?` _keyword_ `:` _parameter_ `,` _keywords_        # Optional keyword

_var-name_ ::= /[a-z]\w*/
```

### Parameters

A parameter can be a type or a pair of type and variable name.
Variable name can be used for documentation.

### Examples

```
# Two required positional `Integer` parameters, and returns `String`
(Integer, Integer) -> String

# Two optional parameters `size` and `name`.
# `name` is a optional parameter with optional type so that developer can omit, pass a string, or pass `nil`.
(?Integer size, ?String? name) -> String

# Method type with a rest parameter
(*Integer, Integer) -> void

# `size` is a required keyword, with variable name of `sz`.
# `name` is a optional keyword.
# `created_at` is a optional keyword, and the value can be `nil`.
(size: Integer sz, ?name: String, ?created_at: Time?) -> void
```

## Members

```markdown
_member_ ::= _ivar-member_                # Ivar definition
           | _method-member_              # Method definition
           | _attribute-member_           # Attribute definition
           | _include-member_             # Mixin (include)
           | _extend-member_              # Mixin (extend)
           | _prepend-member_             # Mixin (prepend)
           | _alias-member_               # Alias
           | `public`                     # Public
           | `private`                    # Private

_ivar-member_ ::= _ivar-name_ `:` _type_

_method-member_ ::= `def` _method-name_ `:` _method-types_            # Instance method
                  | `def self.` _method-name_ `:` _method-types_      # Singleton method
                  | `def self?.` _method-name_ `:` _method-types_     # Singleton and instance method

_method-types_ ::=                                                       # Empty
                 | `super`                                               # `super` overloading
                 | _type-parameters_ _method-type_ `|` _method-types_    # Overloading types

_type-parameters_ ::=                                                 # Empty
                    | `[` _type-variable_ `,` ... `]`

_attribute-member_ ::= _attribute-type_ _method-name_ `:` _type_                     # Attribute
                     | _attribute-type_ _method-name_ `(` _ivar-name_ `) :` _type_   # Attribute with variable name specification
                     | _attribute-type_ _method-name_ `() :` _type_                  # Attribute without variable

_attribute-type_ ::= `attr_reader` | `attr_writer` | `attr_accessor`

_include-member_ ::= `include` _class-name_ _type-arguments_
                   | `include` _interface-name_ _type-arguments_
_extend-member_ ::= `extend` _class-name_ _type-arguments_
                  | `extend` _interface-name_ _type-arguments_
_prepend-member_ ::= `prepend` _class-name_ _type-arguments_

_alias-member_ ::= `alias` _method-name_ _method-name_
                 | `alias self.` _method-name_ `self.` _method-name_

_ivar-name_ ::= /@\w+/
_method-name_ ::= ...
                | /`[^`]+`/
```

### Ivar definition

An instance variable definition consists of the name of an instance variable and its type.

```
@name: String
@value: Hash[Symbol, Key]
```

### Method definition

Method definition has several syntax variations.

You can write `self.` or `self?.` before the name of the method to specify the kind of method: instance, singleton, or both instance and singleton.

```
def to_s: () -> String                        # Defines a instance method
def self.new: () -> AnObject                  # Defines singleton method
def self?.sqrt: (Numeric) -> Numeric          # self? is for `module_function`s
```

The method type can be connected with `|`s to define an overloaded method.

```
def +: (Float) -> Float
     | (Integer) -> Integer
     | (Numeric) -> Numeric
```

You need extra parentheses on return type to avoid ambiguity.

```
def +: (Float | Integer) -> (Float | Integer)
     | (Numeric) -> Numeric
```

Method types can end with `super` which means the methods from existing definitions.
This is useful to define an _extension_, which adds a new variation to the existing method preserving the original behavior.

### Attribute definition

Attribute definitions help to define methods and instance variables based on the convention of `attr_reader`, `attr_writer` and `attr_accessor` methods in Ruby.

You can specify the name of instance variable using `(@some_name)` syntax and also omit the instance variable definition by specifying `()`.

```
# Defines `id` method and `@id` instance variable.
attr_reader id: Integer
# @id: Integer
# def id: () -> Integer

# Defines `name=` method and `raw_name` instance variable.
attr_writer name (@raw_name) : String
# @raw_name: String
# def name=: (String) -> String

# Defines `people` and `people=` methods, but no instance variable.
attr_accessor people (): Array[Person]
# def people: () -> Array[Person]
# def people=: (Array[Person]) -> Array[Person]
```

### Mixin (include), Mixin (extend), Mixin (prepend)

You can define mixins between class and modules.

```
include Kernel
include Enumerable[String, void]
extend ActiveSupport::Concern
```

You can also `include` or `extend` an interface.

```
include _Hashing
extend _LikeString
```

This allows importing `def`s from the interface to help developer implementing a set of methods.

### Alias

You can define an alias between methods.

```
def map: [X] () { (String) -> X } -> Array[X]
alias collect map                                   # `#collect` has the same type with `map`
```

### `public`, `private`

`public` and `private` allows specifying the visibility of methods.

These work only as _statements_, not per-method specifier.

## Declarations

```markdown
_decl_ ::= _class-decl_                         # Class declaration
         | _module-decl_                        # Module declaration
         | _interface-decl_                     # Interface declaration
         | _extension-decl_                     # Extension declaration
         | _type-alias-decl_                    # Type alias declaration
         | _const-decl_                         # Constant declaration
         | _global-decl_                        # Global declaration

_class-decl_ ::= `class` _class-name_ _module-type-parameters_ _members_ `end`
               | `class` _class-name_ _module-type-parameters_ `<` _class-name_ _type-arguments_ _members_ `end`

_module-decl_ ::= `module` _module-name_ _module-type-parameters_ _members_ `end`
                | `module` _module-name_ _module-type-parameters_ `:` _class-name_ _type-arguments_ _members_ `end`

_interface-decl_ ::= `interface` _interface-name_ _module-type-parameters_ _interface-members_ `end`

_interface-members_ ::= _method-member_              # Method
                      | _include-member_             # Mixin (include)
                      | _alias-member_               # Alias

_extension-decl_ ::= `extension` _class-name_ _type-parameters_ `(` _extension-name_ `)` _members_ `end`

_type-alias-decl_ ::= `type` _alias-name_ `=` _type_

_const-decl_ ::= _const-name_ `:` _type_

_global-decl_ ::= _global-name_ `:` _type_

_const-name_ ::= _namespace_ /[A-Z]\w*/
_global-name_ ::= /$[a-zA-Z]\w+/ | ...

_module-type-parameters_ ::=                                                  # Empty
                           | `[` _module-type-parameter_ `,` ... `]`

_module-type-parameter_ ::= _variance_ _type-variable_
_variance_ ::= `out` | `in`
```

### Class declaration

Class declaration can have type parameters and superclass. When you omit superclass, `::Object` is assumed.

```
class Ref[A] < Object
  attr_reader value: A
  def initialize: (value: A) -> void
end
```

### Module declaration

Module declaration takes optional _self type_ parameter, which defines a constraint about a class when the module is mixed.

```
interface _Each[A, B]
  def each: { (A) -> void } -> B
end

module Enumerable[A, B] : _Each[A, B]
  def count: () -> Integer
end
```

The `Enumerable` module above requires `each` method for enumerating objects.

### Interface declaration

Interface declaration can have parameters but allows only a few of the members.

```
interface _Hashing
  def hash: () -> Integer
  def eql?: (any) -> bool
end
```

There are several limitations which are not described in the grammar.

1. Interface cannot `include` modules
2. Interface cannot have singleton method definitions

```
interface _Foo
  include Bar                  # Error: cannot include modules
  def self.new: () -> Foo      # Error: cannot include singleton method definitions
end
```

### Extension declaration

Extension is to model _open class_.

```
extension Kernel (Pathname)
  def Pathname: (String) -> Pathname
end

extension Array[A] (ActiveSupport)
  def to: (Integer) -> Array[A]
  def from: (Integer) -> Array[A]
  def second: () -> A?
  def third: () -> A?
end
```

### Type alias declaration

You can declare an alias of types.

```
type subject = Attendee | Speaker
type JSON::t = Integer | TrueClass | FalseClass | String | Hash[Symbol, t] | Array[t]
```

### Constant type declaration

You can declare a constant.

```
Person::DefaultEmailAddress: String
```

### Global type declaration

You can declare a global variable.

```
$LOAD_PATH: Array[String]
```

