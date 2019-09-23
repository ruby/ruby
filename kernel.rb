module Kernel
  #
  #  call-seq:
  #     obj.clone(freeze: nil) -> an_object
  #
  #  Produces a shallow copy of <i>obj</i>---the instance variables of
  #  <i>obj</i> are copied, but not the objects they reference.
  #  #clone copies the frozen value state of <i>obj</i>, unless the
  #  +:freeze+ keyword argument is given with a false or true value.
  #  See also the discussion under Object#dup.
  #
  #     class Klass
  #        attr_accessor :str
  #     end
  #     s1 = Klass.new      #=> #<Klass:0x401b3a38>
  #     s1.str = "Hello"    #=> "Hello"
  #     s2 = s1.clone       #=> #<Klass:0x401b3998 @str="Hello">
  #     s2.str[1,4] = "i"   #=> "i"
  #     s1.inspect          #=> "#<Klass:0x401b3a38 @str=\"Hi\">"
  #     s2.inspect          #=> "#<Klass:0x401b3998 @str=\"Hi\">"
  #
  #  This method may have class-specific behavior.  If so, that
  #  behavior will be documented under the #+initialize_copy+ method of
  #  the class.
  #
  def clone(freeze: nil)
    __builtin_rb_obj_clone2(freeze)
  end
end
