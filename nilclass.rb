class NilClass
  #
  #  call-seq:
  #     rationalize(eps = nil)  ->  (0/1)
  #
  #  Returns zero as a Rational:
  #
  #     nil.rationalize # => (0/1)
  #
  #  Argument +eps+ is ignored.
  #
  def rationalize(eps = nil)
    0r
  end

  #
  #  call-seq:
  #     to_c -> (0+0i)
  #
  #  Returns zero as a Complex:
  #
  #     nil.to_c # => (0+0i)
  #
  def to_c
    0i
  end

  #
  #  call-seq:
  #     nil.to_i -> 0
  #
  #  Always returns zero.
  #
  #     nil.to_i   #=> 0
  #
  def to_i
    return 0
  end

  #
  #  call-seq:
  #     nil.to_f    -> 0.0
  #
  #  Always returns zero.
  #
  #     nil.to_f   #=> 0.0
  #
  def to_f
    return 0.0
  end

  #
  #  call-seq:
  #     to_r  ->  (0/1)
  #
  #  Returns zero as a Rational:
  #
  #     nil.to_r # => (0/1)
  #
  def to_r
    0r
  end
end
