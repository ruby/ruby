class Integer
  # call-seq:
  #    -int  ->  integer
  #
  # Returns +int+, negated.
  def -@
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_uminus(self)'
  end

  # call-seq:
  #   ~int  ->  integer
  #
  # One's complement: returns a number where each bit is flipped.
  #
  # Inverts the bits in an Integer. As integers are conceptually of
  # infinite length, the result acts as if it had an infinite number of
  # one bits to the left. In hex representations, this is displayed
  # as two periods to the left of the digits.
  #
  #   sprintf("%X", ~0x1122334455)    #=> "..FEEDDCCBBAA"
  def ~
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_comp(self)'
  end

  def abs
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_abs(self)'
  end

  # call-seq:
  #    int.bit_length  ->  integer
  #
  # Returns the number of bits of the value of +int+.
  #
  # "Number of bits" means the bit position of the highest bit
  # which is different from the sign bit
  # (where the least significant bit has bit position 1).
  # If there is no such bit (zero or minus one), zero is returned.
  #
  # I.e. this method returns <i>ceil(log2(int < 0 ? -int : int+1))</i>.
  #
  #    (-2**1000-1).bit_length   #=> 1001
  #    (-2**1000).bit_length     #=> 1000
  #    (-2**1000+1).bit_length   #=> 1000
  #    (-2**12-1).bit_length     #=> 13
  #    (-2**12).bit_length       #=> 12
  #    (-2**12+1).bit_length     #=> 12
  #    -0x101.bit_length         #=> 9
  #    -0x100.bit_length         #=> 8
  #    -0xff.bit_length          #=> 8
  #    -2.bit_length             #=> 1
  #    -1.bit_length             #=> 0
  #    0.bit_length              #=> 0
  #    1.bit_length              #=> 1
  #    0xff.bit_length           #=> 8
  #    0x100.bit_length          #=> 9
  #    (2**12-1).bit_length      #=> 12
  #    (2**12).bit_length        #=> 13
  #    (2**12+1).bit_length      #=> 13
  #    (2**1000-1).bit_length    #=> 1000
  #    (2**1000).bit_length      #=> 1001
  #    (2**1000+1).bit_length    #=> 1001
  #
  # This method can be used to detect overflow in Array#pack as follows:
  #
  #    if n.bit_length < 32
  #      [n].pack("l") # no overflow
  #    else
  #      raise "overflow"
  #    end
  def bit_length
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_bit_length(self)'
  end

  #  call-seq:
  #     int.even?  ->  true or false
  #
  #  Returns +true+ if +int+ is an even number.
  def even?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_even_p(self)'
  end

  #  call-seq:
  #     int.integer?  ->  true
  #
  #  Since +int+ is already an Integer, this always returns +true+.
  def integer?
    return true
  end

  def magnitude
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_abs(self)'
  end

  #  call-seq:
  #     int.odd?  ->  true or false
  #
  #  Returns +true+ if +int+ is an odd number.
  def odd?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_odd_p(self)'
  end

  #  call-seq:
  #     int.ord  ->  self
  #
  #  Returns the +int+ itself.
  #
  #     97.ord   #=> 97
  #
  #  This method is intended for compatibility to character literals
  #  in Ruby 1.9.
  #
  #  For example, <code>?a.ord</code> returns 97 both in 1.8 and 1.9.
  def ord
    return self
  end

  #  call-seq:
  #     int.to_i    ->  integer
  #
  #  Since +int+ is already an Integer, returns +self+.
  #
  #  #to_int is an alias for #to_i.
  def to_i
    return self
  end

  #  call-seq:
  #     int.to_int  ->  integer
  #
  #  Since +int+ is already an Integer, returns +self+.
  def to_int
    return self
  end

  # call-seq:
  #    int.zero? -> true or false
  #
  # Returns +true+ if +int+ has a zero value.
  def zero?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_zero_p(self)'
  end
end
