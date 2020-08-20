class TrueClass
  #
  # call-seq:
  #   true.to_s   ->  "true"
  #
  # The string representation of <code>true</code> is "true".
  #
  def to_s
    "true".freeze
  end

  alias_method :inspect, :to_s

  #
  #  call-seq:
  #     true | obj   -> true
  #
  #  Or---Returns <code>true</code>. As <i>obj</i> is an argument to
  #  a method call, it is always evaluated; there is no short-circuit
  #  evaluation in this case.
  #
  #     true |  puts("or")
  #     true || puts("logical or")
  #
  #  <em>produces:</em>
  #
  #     or
  #
  def |(bool)
    true
  end
end
