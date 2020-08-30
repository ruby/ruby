class Integer
  def abs
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_int_abs(self)'
  end

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
    Primitive.cexpr! 'int_size(self)'
  end
end
