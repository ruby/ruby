# Frozen Objects

A Ruby object may be made immutable by freezing it with method `#freeze`,
which returns `self`;
method Kernel#frozen? returns whether an object is frozen:

```ruby
a = %w[foo bar] # => ["foo", "bar"]
a.frozen?       # => false
a << 'baz'      # => ["foo", "bar", "baz"]
a.freeze        # => ["foo", "bar", "baz"]
a.frozen?       # => true
a << 'bat'      # Raises FrozenError; can't modify frozen Array
```

A frozen object may not be unfrozen.

In general, an object should be frozen if it should not be modified;
such objects may include:

- Constants.
- Configuration objects.
- Lookup tables.
- Value objects.
- Objects shared across threads/Ractors.
- Strings in libraries.

## Frozen Objects in Ruby

Instances of these Ruby classes are always frozen:

- `Symbol`.
- `Integer`.
- `Float`.
- `Rational`.
- `Complex`.
- `TrueClass`; has one instance: `true`.
- `FalseClass`; has one instance: `false`.
- `NilClass`; has one instance: `nil`.

Other Ruby classes, including container classes (such as Array, Hash, and Set)
are by default not frozen.

\String objects are by default not frozen,
but many Ruby libraries freeze their string objects,
commonly by placing a "magic comment" at the top of source files:

```ruby
# frozen_string_literal: true
```

## Frozen User Objects

Each of these methods freezes `self`:

- Array#freeze
- Object#freeze
- Pathname#freeze

Examples:

```ruby
KEYWORDS = %w[foo bar baz].freeze
# => ["foo", "bar", "baz"]
CONFIG = {foo: 0, bar: 1}.freeze
# => {foo: 0, bar: 1}
```

Freezing string objects enables deduplication, which can save memory and improve performance:

```ruby
'foo'.object_id == 'foo'.object_id               # => false  # Two objects are stored.
'foo'.freeze.object_id == 'foo'.freeze.object_id # => true   # Only one object is stored.
```

\String objects for an entire Ruby source file may be frozen via a "magic comment"
(which must be at the top of the file):

```ruby
# frozen_string_literal: true

'foo'.object_id == 'foo'.object_id # => true
```
