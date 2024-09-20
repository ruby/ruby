class Numeric

  #  call-seq:
  #    real? -> true or false
  #
  #  Returns +true+ if +self+ is a real number (i.e. not Complex).
  #
  def real?
    true
  end

  # call-seq:
  #   real -> self
  #
  # Returns +self+.
  #
  def real
    self
  end

  #  call-seq:
  #    integer? -> true or false
  #
  #  Returns +true+ if +self+ is an Integer.
  #
  #    1.0.integer? # => false
  #    1.integer?   # => true
  #
  def integer?
    false
  end

  #  call-seq:
  #    finite? -> true or false
  #
  #  Returns +true+ if +self+ is a finite number, +false+ otherwise.
  #
  def finite?
    true
  end

  #  call-seq:
  #    infinite? -> -1, 1, or nil
  #
  #  Returns +nil+, -1, or 1 depending on whether +self+ is
  #  finite, <tt>-Infinity</tt>, or <tt>+Infinity</tt>.
  #
  def infinite?
    nil
  end

  # call-seq:
  #   imag -> 0
  #
  # Returns zero.
  #
  def imaginary
    0
  end

  alias imag imaginary

  # call-seq:
  #   conj -> self
  #
  # Returns +self+.
  #
  def conjugate
    self
  end

  alias conj conjugate
end

class Integer
  # call-seq:
  #    -int -> integer
  #
  # Returns +self+, negated.
  def -@
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_uminus(self)'
  end

  # call-seq:
  #   ~int -> integer
  #
  # One's complement:
  # returns the value of +self+ with each bit inverted.
  #
  # Because an integer value is conceptually of infinite length,
  # the result acts as if it had an infinite number of
  # one bits to the left.
  # In hex representations, this is displayed
  # as two periods to the left of the digits:
  #
  #   sprintf("%X", ~0x1122334455)    # => "..FEEDDCCBBAA"
  #
  def ~
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_comp(self)'
  end

  # call-seq:
  #   abs -> integer
  #
  # Returns the absolute value of +self+.
  #
  #   (-12345).abs # => 12345
  #   -12345.abs   # => 12345
  #   12345.abs    # => 12345
  #
  def abs
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_abs(self)'
  end

  # call-seq:
  #   bit_length -> integer
  #
  # Returns the number of bits of the value of +self+,
  # which is the bit position of the highest-order bit
  # that is different from the sign bit
  # (where the least significant bit has bit position 1).
  # If there is no such bit (zero or minus one), returns zero.
  #
  # This method returns <tt>ceil(log2(self < 0 ? -self : self + 1))</tt>>.
  #
  #   (-2**1000-1).bit_length   # => 1001
  #   (-2**1000).bit_length     # => 1000
  #   (-2**1000+1).bit_length   # => 1000
  #   (-2**12-1).bit_length     # => 13
  #   (-2**12).bit_length       # => 12
  #   (-2**12+1).bit_length     # => 12
  #   -0x101.bit_length         # => 9
  #   -0x100.bit_length         # => 8
  #   -0xff.bit_length          # => 8
  #   -2.bit_length             # => 1
  #   -1.bit_length             # => 0
  #   0.bit_length              # => 0
  #   1.bit_length              # => 1
  #   0xff.bit_length           # => 8
  #   0x100.bit_length          # => 9
  #   (2**12-1).bit_length      # => 12
  #   (2**12).bit_length        # => 13
  #   (2**12+1).bit_length      # => 13
  #   (2**1000-1).bit_length    # => 1000
  #   (2**1000).bit_length      # => 1001
  #   (2**1000+1).bit_length    # => 1001
  #
  # For \Integer _n_,
  # this method can be used to detect overflow in Array#pack:
  #
  #   if n.bit_length < 32
  #     [n].pack('l') # No overflow.
  #   else
  #     raise 'Overflow'
  #   end
  #
  def bit_length
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_bit_length(self)'
  end

  #  call-seq:
  #    even? -> true or false
  #
  #  Returns +true+ if +self+ is an even number, +false+ otherwise.
  def even?
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_even_p(self)'
  end

  #  call-seq:
  #    integer? -> true
  #
  #  Since +self+ is already an \Integer, always returns +true+.
  def integer?
    true
  end

  alias magnitude abs

  #  call-seq:
  #    odd? -> true or false
  #
  #  Returns +true+ if +self+ is an odd number, +false+ otherwise.
  def odd?
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_odd_p(self)'
  end

  #  call-seq:
  #    ord -> self
  #
  #  Returns +self+;
  #  intended for compatibility to character literals in Ruby 1.9.
  def ord
    self
  end

  #  call-seq:
  #    size -> integer
  #
  #  Returns the number of bytes in the machine representation of +self+;
  #  the value is system-dependent:
  #
  #    1.size             # => 8
  #    -1.size            # => 8
  #    2147483647.size    # => 8
  #    (256**10 - 1).size # => 10
  #    (256**20 - 1).size # => 20
  #    (256**40 - 1).size # => 40
  #
  def size
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_size(self)'
  end

  # call-seq:
  #   times {|i| ... } -> self
  #   times            -> enumerator
  #
  # Calls the given block +self+ times with each integer in <tt>(0..self-1)</tt>:
  #
  #   a = []
  #   5.times {|i| a.push(i) } # => 5
  #   a                        # => [0, 1, 2, 3, 4]
  #
  # With no block given, returns an Enumerator.
  def times
    Primitive.attr! :inline_block
    unless defined?(yield)
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, int_dotimes_size)'
    end
    i = 0
    while i < self
      yield i
      i = i.succ
    end
    self
  end

  #  call-seq:
  #    to_i -> self
  #
  #  Returns +self+ (which is already an \Integer).
  def to_i
    self
  end

  #  call-seq:
  #    to_int -> self
  #
  #  Returns +self+ (which is already an \Integer).
  def to_int
    self
  end

  # call-seq:
  #   zero? -> true or false
  #
  # Returns +true+ if +self+ has a zero value, +false+ otherwise.
  def zero?
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_int_zero_p(self)'
  end

  #  call-seq:
  #    ceildiv(numeric) -> integer
  #
  #  Returns the result of division +self+ by +numeric+.
  #  rounded up to the nearest integer.
  #
  #    3.ceildiv(3)   # => 1
  #    4.ceildiv(3)   # => 2
  #
  #    4.ceildiv(-3)  # => -1
  #    -4.ceildiv(3)  # => -1
  #    -4.ceildiv(-3) # => 2
  #
  #    3.ceildiv(1.2) # => 3
  #
  def ceildiv(other)
    -div(0 - other)
  end

  #
  # call-seq:
  #   numerator -> self
  #
  # Returns +self+.
  #
  def numerator
    self
  end

  # call-seq:
  #   denominator -> 1
  #
  # Returns +1+.
  def denominator
    1
  end
end

class Float

  # call-seq:
  #   to_f -> self
  #
  #  Returns +self+ (which is already a \Float).
  def to_f
    self
  end

  #  call-seq:
  #    float.abs ->  float
  #
  #  Returns the absolute value of +self+:
  #
  #    (-34.56).abs # => 34.56
  #    -34.56.abs   # => 34.56
  #    34.56.abs    # => 34.56
  #
  def abs
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_float_abs(self)'
  end

  def magnitude
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_float_abs(self)'
  end

  # call-seq:
  #   -float -> float
  #
  # Returns +self+, negated.
  #
  def -@
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_float_uminus(self)'
  end

  #  call-seq:
  #    zero? -> true or false
  #
  #  Returns +true+ if +self+ is 0.0, +false+ otherwise.
  def zero?
    Primitive.attr! :leaf
    Primitive.cexpr! 'RBOOL(FLOAT_ZERO_P(self))'
  end

  #  call-seq:
  #    positive? -> true or false
  #
  #  Returns +true+ if +self+ is greater than 0, +false+ otherwise.
  def positive?
    Primitive.attr! :leaf
    Primitive.cexpr! 'RBOOL(RFLOAT_VALUE(self) > 0.0)'
  end

  #  call-seq:
  #    negative? -> true or false
  #
  #  Returns +true+ if +self+ is less than 0, +false+ otherwise.
  def negative?
    Primitive.attr! :leaf
    Primitive.cexpr! 'RBOOL(RFLOAT_VALUE(self) < 0.0)'
  end

end
