class Symbol
  # call-seq:
  #   to_s -> string
  #
  # Returns a frozen string representation of +self+ (not including the leading colon):
  #
  #   :foo.to_s # => "foo"
  #   :foo.name.frozen? # => true
  #
  # Related: Symbol#inspect
  def to_s
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_sym2str(self)'
  end

  alias id2name to_s
  alias name to_s

  # call-seq:
  #   empty? -> true or false
  #
  # Returns +true+ if +self+ is <tt>:''</tt>, +false+ otherwise.
  def empty?
    Primitive.attr! :leaf
    Primitive.cexpr! 'RBOOL(self == STATIC_ID2SYM(idNULL))'
  end

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
