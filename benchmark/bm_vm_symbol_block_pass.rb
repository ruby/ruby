class C
  1000.times {|i|
    eval("def i#{i};end")
  }
end

c = C.new
m = C.instance_methods(false)
5_000.times do
  m.each do |n|
    c.tap(&n)
  end
end
