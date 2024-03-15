def yaaay
  "yay!"
end

module Foo
  def self.foo
    yaaay
  end
end

eval 'def foo; "foo"; end'

Foo.foo # Should not raise NameError

foo

module Bar
  def self.bar
    foo
  end
end

Bar.bar

$def_retval_in_namespace = def boooo
  "boo"
end

module Baz
  def self.baz
    raise "#{$def_retval_in_namespace}"
  end
end
