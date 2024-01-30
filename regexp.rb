class Regexp
  # call-seq:
  #   match?(string) -> true or false
  #   match?(string, offset = 0) -> true or false
  #
  # Returns <code>true</code> or <code>false</code> to indicate whether the
  # regexp is matched or not without updating $~ and other related variables.
  # If the second parameter is present, it specifies the position in the string
  # to begin the search.
  #
  #    /R.../.match?("Ruby")    # => true
  #    /R.../.match?("Ruby", 1) # => false
  #    /P.../.match?("Ruby")    # => false
  #    $&                       # => nil
  def match?(str, offset = 0)
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_reg_match_p(self, str, NUM2LONG(offset))'
  end
end
