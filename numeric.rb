class Numeric
  #
  #  call-seq:
  #     num.real?  ->  true or false
  #
  #  Returns +true+ if +num+ is a real number (i.e. not Complex).
  #
  def real?
    true
  end

  #
  # call-seq:
  #    num.real  ->  self
  #
  # Returns self.
  #
  def real
    self
  end

  #
  #  call-seq:
  #     num.integer?  ->  true or false
  #
  #  Returns +true+ if +num+ is an Integer.
  #
  #      1.0.integer?   #=> false
  #      1.integer?     #=> true
  #
  def integer?
    false
  end

  #
  #  call-seq:
  #     num.finite?  ->  true or false
  #
  #  Returns +true+ if +num+ is a finite number, otherwise returns +false+.
  #
  def finite?
    true
  end

  #
  #  call-seq:
  #     num.infinite?  ->  -1, 1, or nil
  #
  #  Returns +nil+, -1, or 1 depending on whether the value is
  #  finite, <code>-Infinity</code>, or <code>+Infinity</code>.
  #
  def infinite?
    nil
  end

  #
  # call-seq:
  #    num.imag       ->  0
  #    num.imaginary  ->  0
  #
  # Returns zero.
  #
  def imaginary
    0
  end

  alias imag imaginary

  #
  # call-seq:
  #    num.conj       ->  self
  #    num.conjugate  ->  self
  #
  # Returns self.
  #
  def conjugate
    self
  end

  alias conj conjugate
end

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

  # call-seq:
  #    int.abs        ->  integer
  #    int.magnitude  ->  integer
  #
  # Returns the absolute value of +int+.
  #
  #    (-12345).abs   #=> 12345
  #    -12345.abs     #=> 12345
  #    12345.abs      #=> 12345
  #
  # Integer#magnitude is an alias for Integer#abs.
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
    true
  end

  alias magnitude abs
=begin
  def magnitude
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_abs(self)'
  end
=end

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
    self
  end

  #
  #  Document-method: Integer#size
  #  call-seq:
  #     int.size  ->  int
  #
  #  Returns the number of bytes in the machine representation of +int+
  #  (machine dependent).
  #
  #     1.size               #=> 8
  #     -1.size              #=> 8
  #     2147483647.size      #=> 8
  #     (256**10 - 1).size   #=> 10
  #     (256**20 - 1).size   #=> 20
  #     (256**40 - 1).size   #=> 40
  #
  def size
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_size(self)'
  end

  #  call-seq:
  #     int.to_i    ->  integer
  #
  #  Since +int+ is already an Integer, returns +self+.
  #
  #  #to_int is an alias for #to_i.
  def to_i
    self
  end

  #  call-seq:
  #     int.to_int  ->  integer
  #
  #  Since +int+ is already an Integer, returns +self+.
  def to_int
    self
  end

  # call-seq:
  #    int.zero? -> true or false
  #
  # Returns +true+ if +int+ has a zero value.
  def zero?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_zero_p(self)'
  end

  #  call-seq:
  #    ceildiv(other) -> integer
  #
  #  Returns the result of division +self+ by +other+. The result is rounded up to the nearest integer.
  #
  #    3.ceildiv(3) # => 1
  #    4.ceildiv(3) # => 2
  #
  #    4.ceildiv(-3) # => -1
  #    -4.ceildiv(3) # => -1
  #    -4.ceildiv(-3) # => 2
  #
  #    3.ceildiv(1.2) # => 3
  def ceildiv(other)
    -div(-other)
  end

  #
  # call-seq:
  #    int.numerator  ->  self
  #
  # Returns self.
  #
  def numerator
    self
  end

  #
  # call-seq:
  #    int.denominator  ->  1
  #
  # Returns 1.
  #
  def denominator
    1
  end
end

#  call-seq:
#    Integer.try_convert(object) -> object, integer, or nil
#
#  If +object+ is an \Integer object, returns +object+.
#    Integer.try_convert(1) # => 1
#
#  Otherwise if +object+ responds to <tt>:to_int</tt>,
#  calls <tt>object.to_int</tt> and returns the result.
#    Integer.try_convert(1.25) # => 1
#
#  Returns +nil+ if +object+ does not respond to <tt>:to_int</tt>
#    Integer.try_convert([]) # => nil
#
#  Raises an exception unless <tt>object.to_int</tt> returns an \Integer object.
#
def Integer.try_convert(num)
=begin
  Primitive.attr! 'inline'
  Primitive.cexpr! 'rb_check_integer_type(num)'
=end
end if false

class Float
  #
  #	The base of the floating point, or number of unique digits used to
  #	represent the number.
  #
  #  Usually defaults to 2 on most systems, which would represent a base-10 decimal.
  #
  RADIX = Primitive.cconst! 'INT2FIX(FLT_RADIX)'

  #
  # The number of base digits for the +double+ data type.
  #
  # Usually defaults to 53.
  #
  MANT_DIG = Primitive.cconst! 'INT2FIX(DBL_MANT_DIG)'

  #
  #	The minimum number of significant decimal digits in a double-precision
  #	floating point.
  #
  #	Usually defaults to 15.
  #
  DIG = Primitive.cconst! 'INT2FIX(DBL_DIG)'

  #
  #	The smallest possible exponent value in a double-precision floating
  #	point.
  #
  #	Usually defaults to -1021.
  #
  MIN_EXP = Primitive.cconst! 'INT2FIX(DBL_MIN_EXP)'

  #
  #	The largest possible exponent value in a double-precision floating
  #	point.
  #
  #	Usually defaults to 1024.
  #
  MAX_EXP = Primitive.cconst! 'INT2FIX(DBL_MAX_EXP)'

  #
  #	The smallest negative exponent in a double-precision floating point
  #	where 10 raised to this power minus 1.
  #
  #	Usually defaults to -307.
  #
  MIN_10_EXP = Primitive.cconst! 'INT2FIX(DBL_MIN_10_EXP)'

  #
  #	The largest positive exponent in a double-precision floating point where
  #	10 raised to this power minus 1.
  #
  #	Usually defaults to 308.
  #
  MAX_10_EXP = Primitive.cconst! 'INT2FIX(DBL_MAX_10_EXP)'

  #
  #	The smallest positive normalized number in a double-precision floating point.
  #
  #	Usually defaults to 2.2250738585072014e-308.
  #
  #	If the platform supports denormalized numbers,
  #	there are numbers between zero and Float::MIN.
  #	0.0.next_float returns the smallest positive floating point number
  #	including denormalized numbers.
  #
  MIN = Primitive.cconst! 'DBL2NUM(DBL_MIN)'

  #
  #	The largest possible integer in a double-precision floating point number.
  #
  #	Usually defaults to 1.7976931348623157e+308.
  #
  MAX = Primitive.cconst! 'DBL2NUM(DBL_MAX)';

  #
  #	The difference between 1 and the smallest double-precision floating
  #	point number greater than 1.
  #
  #	Usually defaults to 2.2204460492503131e-16.
  #
  EPSILON = Primitive.cconst! 'DBL2NUM(DBL_EPSILON)'

  #
  #	An expression representing positive infinity.
  #
  INFINITY = Primitive.cconst! 'DBL2NUM(HUGE_VAL)'

  #
  #	An expression representing a value which is "not a number".
  #
  NAN = Primitive.cconst! 'DBL2NUM(nan(""))'

  #
  # call-seq:
  #    float.to_f  ->  self
  #
  # Since +float+ is already a Float, returns +self+.
  #
  def to_f
    self
  end

  #
  #  call-seq:
  #     float.abs        ->  float
  #     float.magnitude  ->  float
  #
  #  Returns the absolute value of +float+.
  #
  #     (-34.56).abs   #=> 34.56
  #     -34.56.abs     #=> 34.56
  #     34.56.abs      #=> 34.56
  #
  #  Float#magnitude is an alias for Float#abs.
  #
  def abs
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_float_abs(self)'
  end

  def magnitude
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_float_abs(self)'
  end

  #
  # call-seq:
  #    -float  ->  float
  #
  # Returns +float+, negated.
  #
  def -@
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_float_uminus(self)'
  end

  #
  #  call-seq:
  #     float.zero?  ->  true or false
  #
  #  Returns +true+ if +float+ is 0.0.
  #
  def zero?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'RBOOL(FLOAT_ZERO_P(self))'
  end

  #
  #  call-seq:
  #     float.positive?  ->  true or false
  #
  #  Returns +true+ if +float+ is greater than 0.
  #
  def positive?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'RBOOL(RFLOAT_VALUE(self) > 0.0)'
  end

  #
  #  call-seq:
  #     float.negative?  ->  true or false
  #
  #  Returns +true+ if +float+ is less than 0.
  #
  def negative?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'RBOOL(RFLOAT_VALUE(self) < 0.0)'
  end

end
