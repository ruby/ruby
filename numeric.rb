class Numeric
  #
  #  call-seq:
  #     num.clone(freeze: true)  ->  num
  #
  #  Returns the receiver.  +freeze+ cannot be +false+.
  #
  def clone(freeze: true)
    __builtin_rb_immutable_obj_clone(freeze)
  end
end
