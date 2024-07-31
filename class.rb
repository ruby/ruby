class Class
  def new(...)
    Primitive.pop!(
      Primitive.send_delegate!(
        Primitive.dup!(Primitive.rb_class_alloc2), :initialize, ...))
  end
end

class BasicObject
  def initialize
  end
end
