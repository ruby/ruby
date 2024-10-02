class NilClass
  #
  #  call-seq:
  #     nil.not_nil!
  #
  #  Always raises a TypeError.
  #
  #     nil.not_nil!   #=> TypeError: Called `not_nil!` on nil
  #
  def not_nil!
    raise TypeError, "Called `not_nil!` on nil"
  end

  alias not_nil then

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
end
