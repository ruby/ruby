require "marshal"
include Marshal
a = 25.6;
pt = Struct.new('point', :x,:y);
x = pt.new(10, 10)
y = pt.new(20, 20)
rt = Struct.new('rectangle', :origin,:corner);
z = rt.new(x, y)
c = Object.new
s = [a, x, z, c, c, "fff"];
print s.inspect;
d = dumps(s);
print load(d).inspect
