include Marshal
a = 25.6;
pt = Struct.new('Point', :x,:y);
x = pt.new(10, 10)
y = pt.new(20, 20)
rt = Struct.new('Rectangle', :origin,:corner);
z = rt.new(x, y)
c = Object.new
s = [a, x, z, c, c, "fff"];
p s
d = dump(s);
p d
p load(d)
