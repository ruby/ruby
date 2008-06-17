assert_equal 'A', %q{
  class A
    @@a = 'A'
    def a=(x)
      @@a = x
    end
    def a
      @@a
    end
  end

  B = A.dup
  B.new.a = 'B'
  A.new.a
}, '[ruby-core:17019]'
