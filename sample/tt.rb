module Print
  print("in Print\n")
  def println(*args)
    for a in args
      print(a)
    end
    print("\n")
  end def

  def println2(*args)
    print(*args)
    print("\n")
  end def
end module

module Print2
  def println(*args)
    print("pr2: ");
    super
  end
end

module Print3
  include Print2
  def println(*args)
    print("pr3: ");
    super
  end
end

include Print, Print2, Print3

println2("in TopLevel")

print("a: ", $OPT_test, "\n")
printf("%10.5g: %*s -> 0x%x\n", 123345, -10, Print, Print.id);

println("a+ matches aaa at ", "bccAAaaa" =~ /a+/)
ttt = "this is a ´Á»ú ´Á»ú"
if offset = (ttt =~ /this ([^ ]*) (.*)/)
  println("0 = ", $&);
  println("1 = ", $1);
  println("2 = ", $2);
end

class Fib:Object
  print("in Fib:Object\n")

  def Fib.test(*args)
    println("in Fib.test")

    if args; println(*args) end
    args = args.grep(/^c/)
    super(*args)
  end def

  def init
    println("in Fib.init");
  end def

  def fib(n)
    a =0; b = 1

    while b <= n
      c = a; a = b; b = c+b
    end while
    return b
  end def
end

def Object.test(*args)
  println("in Object.test")
  if args; println(*args) end
end

Fib.test("abc", "def", "aaa", "ccc")
println("1:", 0x3fffffffa)
println("2:", 0x3ffffffa)
#println("3:", 0x40000000+0x40000000)

fib = Fib.new

fib.init
print(Fib, ":")

#for i in 1 .. 100
#  fib.fib(90000)
#end

println(fib.fib(9000))

def tt
  for i in 1..10
    println("i:", i);
    yield(i);
  end
end

test = do tt() using i
  if i == 2; break end
end

println([1,2,3,4].join(":"))
