module A
end

module A::B
end

module A::B::C
end

module A
  include(B.new)

  def foo
    :bar
  end
end
