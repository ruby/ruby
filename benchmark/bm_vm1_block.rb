def m
  yield
end

i=0
while i<30000000 # while loop 1
  i+=1
  m{
  }
end