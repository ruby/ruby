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
