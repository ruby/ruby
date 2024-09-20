def foo = puts "Hello"

def foo() = puts "Hello"

def foo(x) = puts x

def obj.foo = puts "Hello"

def obj.foo() = puts "Hello"

def obj.foo(x) = puts x

def rescued(x) = raise "to be caught" rescue "instance #{x}"

def self.rescued(x) = raise "to be caught" rescue "class #{x}"
