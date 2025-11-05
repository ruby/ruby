module Target
  def self.foo
    "fooooo"
  end
end

module Foo
  def self.callee
    lambda do
      Target.foo
    end
  end
end

