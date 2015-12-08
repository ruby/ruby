i = 0
@ret = [ "foo", true, false, :sym, 6, nil, 0.1, 0xffffffffffffffff ]
def foo(i)
  @ret[i % @ret.size]
end

while i<6_000_000 # while loop 2
  case foo(i)
  when "foo" then :foo
  when true then true
  when false then false
  when :sym then :sym
  when 6 then :fix
  when nil then nil
  when 0.1 then :float
  when 0xffffffffffffffff then :big
  end
  i += 1
end
