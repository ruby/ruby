def add(a, b)
  a + b
end

if __FILE__ == $0
  result = add(3, 5)
  puts "Three plus five is #{ result }"
end
