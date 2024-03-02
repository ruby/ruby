class Class
  def new(...)
    obj = Primitive.rb_class_alloc2
    Primitive.send_delegate!(obj, :initialize, ...)
    obj
  end
end

class BasicObject
  def initialize
  end
end
