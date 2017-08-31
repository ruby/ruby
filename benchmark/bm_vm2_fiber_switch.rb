# based on benchmark for [ruby-core:65518] [Feature #10341] by Knut Franke
fib = Fiber.new do
  loop { Fiber.yield }
end
i = 0
while i< 6_000_000 # benchmark loop 2
  i += 1
  fib.resume
end
