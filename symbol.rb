class Symbol
  # call-seq:
  #   to_sym -> self
  #
  # Returns +self+.
  #
  # Symbol#intern is an alias for Symbol#to_sym.
  #
  # Related: String#to_sym.
  def to_sym
    self
  end

  alias intern to_sym
end
