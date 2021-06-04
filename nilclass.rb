class NilClass
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
