class Symbol
  # call-seq:
  #   to_s -> string
  #
  # Returns a string representation of +self+ (not including the leading colon):
  #
  #   :foo.to_s # => "foo"
  #
  # Related: Symbol#inspect, Symbol#name.
  def to_s
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_sym_to_s(self)'
  end

  alias id2name to_s

  # call-seq:
  #   to_sym -> self
  #
  # Returns +self+.
  #
  # Related: String#to_sym.
  def to_sym
    self
  end

  alias intern to_sym
end
