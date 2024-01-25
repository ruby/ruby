class Module
  # call-seq:
  #    mod.name    -> string
  #
  # Returns the name of the module <i>mod</i>.  Returns nil for anonymous modules.
  def name
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_mod_name(self)'
  end
end
