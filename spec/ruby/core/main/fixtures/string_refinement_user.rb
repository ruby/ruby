using StringRefinement

module MainSpecs
  DATA[:in_module] = 'hello'.foo

  def self.call_foo(x)
    x.foo
  end
end

MainSpecs::DATA[:toplevel] = 'hello'.foo
