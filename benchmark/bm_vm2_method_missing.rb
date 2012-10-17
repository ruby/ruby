class C
  def method_missing mid
  end
end

obj = C.new

i = 0
while i<6_000_000 # benchmark loop 2
  i += 1
  obj.m; obj.m; obj.m; obj.m; obj.m; obj.m; obj.m; obj.m;
end
