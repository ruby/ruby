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

  #  Document-method: Integer#times
  #  call-seq:
  #     int.times {|i| block }  ->  self
  #     int.times               ->  an_enumerator
  #
  #  Iterates the given block +int+ times, passing in values from zero to
  #  <code>int - 1</code>.
  #
  #  If no block is given, an Enumerator is returned instead.
  #
  #     5.times {|i| print i, " " }   #=> 0 1 2 3 4
  def times
    unless Primitive.block_given_p
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, int_dotimes_size)'
    end
    i = 0
    while i < self
      yield i
      i += 1
    end
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
