require 'delegate'

class ExtArray<DelegateClass(Array)
  def initialize()
    super([])
  end
end

ary = ExtArray.new
p ary.class
ary.push 25
p ary
ary.push 42
ary.each {|x| p x}

foo = Object.new
def foo.test
  25
end
def foo.iter
  yield self
end
def foo.error
  raise 'this is OK'
end
foo2 = SimpleDelegator.new(foo)
p foo2
foo2.instance_eval{print "foo\n"}
p foo.test == foo2.test       # => true
p foo2.iter{[55,true]}        # => true
foo2.error                    # raise error!
