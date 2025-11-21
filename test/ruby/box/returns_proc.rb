module Foo
  def self.foo
    "fooooo"
  end

  def self.callee
    lambda do
      Foo.foo
    end
  end
end

