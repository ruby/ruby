def fact(n)
  return 1 if n == 0
  f = 1
  while n>0
    f *= n
    n -= 1
  end
  return f
end
print fact(ARGV[0].to_i), "\n"
