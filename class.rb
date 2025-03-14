class Class
  def new(...)
    Primitive.attr! :c_trace

    Primitive.pop!(
      Primitive.send_delegate!(
        Primitive.dup!(Primitive.rb_class_alloc2), :initialize, ...))
  end
end

class BasicObject
  def initialize
    Primitive.attr! :c_trace
    nil
  end
end
