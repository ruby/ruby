class Integer
  # call-seq:
  #    int.zero? -> true or false
  #
  # Returns +true+ if +num+ has a zero value.
  def zero?
    Primitive.attr! 'inline'
    Primitive.cexpr! 'int_zero_p(self);'
  end
end
