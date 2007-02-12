i=0
str = 'xxxhogexxx'
while i<6000000 # benchmark loop 2
  /hoge/ =~ str
  i+=1
end
