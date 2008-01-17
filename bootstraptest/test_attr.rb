assert_equal %{ok}, %{
  class A
    attr :m
  end
  begin
    A.new.m(3)
  rescue ArgumentError => e
    print "ok"
  end
}, '[ruby-core:15120]'
