class TrueClass
  #  Document-class: TrueClass
  #
  #  The global value <code>true</code> is the only instance of class
  #  TrueClass and represents a logically true value in
  #  boolean expressions. The class provides operators allowing
  #  <code>true</code> to be used in logical expressions.
  # 
  #
  # call-seq:
  #   true.to_s   ->  "true"
  #
  # The string representation of <code>true</code> is "true".
  #
  def to_s
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_cTrueClass_to_s'
  end

  alias_method :inspect, :to_s

  #
  #  call-seq:
  #     true & obj    -> true or false
  #
  #  And---Returns <code>false</code> if <i>obj</i> is
  #  <code>nil</code> or <code>false</code>, <code>true</code> otherwise.
  #
  def &(obj)
    Primitive.attr! 'inline'
    Primitive.cexpr! 'RTEST(obj)?Qtrue:Qfalse;'
  end

  #
  #  call-seq:
  #     true ^ obj   -> !obj
  #
  #  Exclusive Or---Returns <code>true</code> if <i>obj</i> is
  #  <code>nil</code> or <code>false</code>, <code>false</code>
  #  otherwise.
  #
  def ^(obj)
    Primitive.attr! 'inline'
    Primitive.cexpr! 'RTEST(obj)?Qfalse:Qtrue;'
  end

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
