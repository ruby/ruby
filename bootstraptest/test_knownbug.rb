#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  class C
    define_method(:foo) {
      if block_given?
        :ok
      else
        :ng
      end
    }
  end
  C.new.foo {}
}, '[ruby-core:14813]'

assert_equal 'ok', %q{
  class C
    define_method(:foo) {
      if block_given?
        :ng
      else
        :ok
      end
    }
  end
  C.new.foo
}, '[ruby-core:14813]'

assert_equal 'ok', %q{
  class X < RuntimeError;end
  x = [X]
  begin
   raise X
  rescue *x
   :ok
  end
}, '[ruby-core:14537]'

assert_normal_exit %q{
  "abc".gsub(/./, "a" => "z")
}

assert_normal_exit %q{
  Encoding.compatible?("",0)
}

assert_normal_exit %q{
  "".center(1, "\x80".force_encoding("utf-8"))
}, '[ruby-dev:33807]'

assert_equal 'ok', %q{
  a = lambda {|x, y, &b| b }
  b = a.curry[1]
  if b.call(2){} == nil
    :ng
  else
    :ok
  end
}, '[ruby-core:15551]'

assert_normal_exit %q{
  sprintf("% 0e", 1.0/0.0)
}

assert_normal_exit %q{
  g = Module.enum_for(:new)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  Fiber.new(&Object.method(:class_eval)).resume("foo")
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  Thread.new("foo", &Object.method(:class_eval)).join
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = enum_for(:local_variables)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = enum_for(:block_given?)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = enum_for(:binding)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = "abc".enum_for(:scan, /./)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_equal %q{[:bar, :foo]}, %q{
  def foo
    klass = Class.new do
      define_method(:bar) do
        return :bar
      end
    end
    [klass.new.bar, :foo]
  end
  foo
}, "[ ruby-Bugs-19304 ]"

assert_equal 'ok', %q{
  def a() end
  begin
    if defined?(a(1).a)
      :ng
    else
      :ok
    end
  rescue
    :ng
  end
}, '[ruby-core:16010]'

assert_equal 'ok', %q{
  def a() end
  begin
    if defined?(a::B)
      :ng
    else
      :ok
    end
  rescue
    :ng
  end
}, '[ruby-core:16010]'


assert_equal 'ok', %q{
  class Module
    def my_module_eval(&block)
      module_eval(&block)
    end
  end
  class String
    Integer.my_module_eval do
      def hoge; end
    end
  end
  if Integer.instance_methods(false).map{|m|m.to_sym}.include?(:hoge) &&
     !String.instance_methods(false).map{|m|m.to_sym}.include?(:hoge)
    :ok
  else
    :ng
  end
}, "[ruby-dev:34236]"

assert_equal 'ok', %q{
  def m
    t = Thread.new { while true do // =~ "" end }
    sleep 0.1
    10.times {
      if /((ab)*(ab)*)*(b)/ =~ "ab"*7
        return :ng if !$4
        return :ng if $~.size != 5
      end
    }
    :ok
  ensure
    Thread.kill t
  end
  m
}, '[ruby-dev:34492]'

assert_normal_exit %q{
  begin
    r = 0**-1
    r + r
  rescue
  end
}, '[ruby-dev:34524]'

assert_normal_exit %q{
  begin
    r = Marshal.load("\x04\bU:\rRational[\ai\x06i\x05")
    r + r
  rescue
  end
}, '[ruby-dev:34536]'

