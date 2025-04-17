### Remarks

Just run it with no argument:

```sh
ruby entry.rb
```

I confirmed the following implementations/platforms:

- ruby 3.4.1 (2024-12-25 revision 48d4efcb85) +YJIT +MN +PRISM [arm64-darwin22]
- ruby 3.0.0p0 (2020-12-25 revision 95aff21468) [aarch64-linux-musl]

### Description

Readability is important even for a simple fizz buzz program.

These are the major ingredients of a spaghetti that makes program tasty and valuable but unreadable.

- Many class definitions
- Many method definitions
- Many method calls
- Many variables
- Conditional branches

These are what is acceptable for a readable program.

- Many modules: Using only a single module in a program is not good.
- Many constants: Better than magic numbers.
- Module#include: Mixins are what module is for.
- Many file loads: Usually better than loading a large file only once.
- Minimal method calls: Needed for printing output.

This program is doing something slightly difficult in the last few lines: print output and load ruby program.
In contrast, the rest part of this program is extremely simple and easy. Module definition, constant definition and module inclusion. That's all.

### Internals

Called methods

- `Module#include`
- `Array#join`
- `Kernel#printf`
- `Kernel#load`

Deeply nested module chain to avoid constant reassignment

```ruby
10.times do
  module Root
    module Chain
      module X; end
      module Y; end
      module Z; end
    end
  end
  include Root

  module Chain::Chain
    # Not a constant reassignment because Chain::Chain is always a new module
    X = Chain::Y
    Y = Chain::Z
    Z = Chain::X
  end
  include Chain
  p x: X, chain: Chain
end
```

Constant allocation

| Constant               | Purpose                 |
| ---------------------- | ----------------------- |
| A                      | Loop condition          |
| B                      | Format (!Fizz && !Buzz) |
| C, E, F                | Fizz rotation           |
| D, G, H, I, J          | Buzz rotation           |
| K, M, O, Q, S, U, W, Y | Iteration bits          |
| L, N, P, R, T, V, X, Z | Temporary carry bits    |

Instruction sequence with constant lookup magic

```ruby
# B = 1 if A
If::A::Set::B = On

# B = 1 if !A
If::A::Not::Set::B = On

# C = 1 if !A && B
If::A::Not::B::Set::C = On

# C = 1 if !A && !B
If::A::Not::B::Not::Set::C = On
```

Loop with `load __FILE__`

```ruby
# A::NEXT is __FILE__ or '/dev/null'
load A::NEXT
```

### Limitation

Needs `/dev/null`
