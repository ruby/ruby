class A
end

class << a
end

class << a
  b
end

class A::B
end

class A::B::C
end

class A < B
end

class A < B::C
end

class A::B < C::D
end

class A
  include(B.new)

  def foo
    :bar
  end
end

class ::A
end
