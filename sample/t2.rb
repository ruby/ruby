#print("in Print\n")
def t2() end

def println(*args)
  for a in args
    t2()
    print(a)
  end
  print("\n")
end def

def tt
  for i in 1..10
    println("i:", i);
    yield(i);
  end
end

test = 
do tt() using i
  if i == 3; break end
  println("ttt: ", i);
end
#exit()
