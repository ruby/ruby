class Class
  # call-seq:
  #    class.superclass -> a_super_class or nil
  #
  # Returns the superclass of <i>class</i>, or <code>nil</code>.
  #
  #    File.superclass          #=> IO
  #    IO.superclass            #=> Object
  #    Object.superclass        #=> BasicObject
  #    class Foo; end
  #    class Bar < Foo; end
  #    Bar.superclass           #=> Foo
  #
  # Returns nil when the given class does not have a parent class:
  #
  #    BasicObject.superclass   #=> nil
  #
  #--
  # Returns the superclass of \a klass. Equivalent to \c Class\#superclass in Ruby.
  #
  # It skips modules.
  # \param[in] klass a Class object
  # \return the superclass, or \c Qnil if \a klass does not have a parent class.
  # \sa rb_class_get_superclass
  #++
  def superclass
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_class_superclass(self)'
  end
end
