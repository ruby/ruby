class A a = 1 end

class A; ensure; end

class A; rescue; else; ensure; end

class A < B
a = 1
end

class << not foo
end

class A; class << self; ensure; end; end

class A; class << self; rescue; else; ensure; end; end

class << foo.bar
end

class << foo.bar;end

class << self
end

class << self;end

class << self
1 + 2
end

class << self;1 + 2;end

class A < B[1]
end
