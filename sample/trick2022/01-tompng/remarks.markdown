### Remarks

Just run it with no argument:

    ruby entry.rb

Or run it with one non-ascii half-width character argument:

    ruby entry.rb ⬮
    ruby entry.rb 𓆡

I confirmed the following implementations/platforms:

* ruby 3.0.0p0 (2020-12-25 revision 95aff21468) [x86_64-darwin19]
* ruby 3.1.0p0 (2021-12-25 revision fb4df44d16) [x86_64-darwin20]

### Description

This program is an aquatic quine.
Some characters in the code are overwritten with `" "`, but this program can restore the missing parts.
Every frame of this animation is an executable ruby program that let fishes start swimming again from their current position.

### Internals

#### Error Correction

Error correction is performed for each block of length 135.
It consists of 89 kinds of characters(`[*('!'..'W'), '[', *(']'..'}')]`) and satisfies the following constraint.

```
matrix(size: 45x135) * block_vector(size: 135) % 89 == zero_vector(size: 45)
```

To restore the missing characters in the block, we need to solve a linear equation problem in modulo 89.
This can be achieved by using bundled gem 'matrix' and overwriting some methods.

```ruby
require 'matrix'
matrix = Matrix[[3, 1, 4], [1, 5, 9], [2, 6, 5]]
class Integer
  def quo(x) = self * x.pow(87, 89) % 89 # Fermat's little theorem. 89 is a prime number.
  def abs() = [self % 89, 89 - self % 89].min # To avoid division by multiple of 89.
end
answer = matrix.lup.solve([1, 2, 3]) #=> Vector[24, 42, 83]
(matrix * answer).map { _1 % 89 } #=> Vector[1, 2, 3]
```

#### Resuming Animation

The entire animation of this fish tank is a loop of 960 frames.
This program uses position of the floating bubbles to detect current frame number from the executed source code.
