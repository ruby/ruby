class Symbol
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
