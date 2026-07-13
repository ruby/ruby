assert_normal_exit %q{
  ary = (1..10).to_a
  ary.permutation(2) {|x|
    if x == [1,2]
      ObjectSpace.each_object(String) {|s|
        s.clear if !s.frozen? && (s.length == 40 || s.length == 80)
      }
    end
  }
}, '[ruby-dev:31982]'

assert_normal_exit %q{
  ary = (1..100).to_a
  ary.permutation(2) {|x|
    if x == [1,2]
      ObjectSpace.each_object(Array) {|o| o.clear if o == ary && o.object_id != ary.object_id }
    end
  }
}, '[ruby-dev:31985]'

assert_normal_exit %q{
  ObjectSpace.define_finalizer("") do
    Thread::Mutex.new.lock
  end
}, '[ruby-dev:44049]'

assert_normal_exit %q{
  ObjectSpace.define_finalizer("") do
    Thread.new {}
  end
}, '[ruby-core:37858]'
