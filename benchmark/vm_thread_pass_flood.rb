# n.b. this is a good test for GVL when pinned to a single CPU

1000.times{
  Thread.new{loop{Thread.pass}}
}

i = 0
while i<10000
  i += 1
end
