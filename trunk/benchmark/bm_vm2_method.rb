def m
  nil
end

i=0
while i<6000000 # benchmark loop 2
  i+=1
  m; m; m; m; m; m; m; m;
end
