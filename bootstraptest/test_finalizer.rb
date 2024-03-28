assert_normal_exit %q{
a1,a2,b1,b2=Array.new(4){""}
ObjectSpace.define_finalizer(b2,proc{})
ObjectSpace.define_finalizer(b1,proc{b1.inspect})

ObjectSpace.define_finalizer(a2,proc{a1.inspect})
ObjectSpace.define_finalizer(a1,proc{})
}, '[ruby-dev:35778]'

assert_equal 'true', %q{
  obj = Object.new
  id = obj.object_id

  ObjectSpace.define_finalizer(obj, proc { |i| print(id == i) })
  nil
}
