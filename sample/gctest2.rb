# GC stress test
def cons(car, cdr)
   car::cdr
end

def car(x)
  x.car
end

def cdr(x)
  x.cdr
end

def reverse1(x, y)
  if x == nil then
    y 
  else 
    reverse1(cdr(x), cons(car(x), y))
  end
end

def reverse(x)
  reverse1(x, nil)
end

def ints(low, up)
  if low > up
     nil
  else
     cons(low, ints(low+1, up))
  end
end

def print_int_list(x)
  if x == nil
    print("NIL\n")
  else
    print(car(x))
    if cdr(x)
      print(", ")
      print_int_list(cdr(x))
    else
      print("\n")
    end
  end
end

print("start\n")

a = ints(1, 100)
print_int_list(a)
b = ints(1, 50)
print_int_list(b)
print_int_list(reverse(a))
print_int_list(reverse(b))
for i in 1 .. 100
  b = reverse(reverse(b))
#  print(i, ": ")
#  print_int_list(b)
end
print("a: ")
print_int_list(a)
print("b: ")
print_int_list(b)
print("reverse(a): ")
print_int_list(reverse(a))
print("reverse(b): ")
print_int_list(reverse(b))
a = b = nil
print("finish\n")
GC.start()
