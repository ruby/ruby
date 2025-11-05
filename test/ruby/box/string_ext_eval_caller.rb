module Baz
  def self.yay
    eval 'String.new.yay'
  end

  def self.yay_with_binding
    suffix = ", yay!"
    eval 'String.new.yay + suffix', binding
  end
end

Baz.yay # should not raise NeMethodError
