# Check performance of fiber creation and transfer.

def make_link(previous)
  Fiber.new do
    while message = previous.resume
      Fiber.yield(message)
    end
  end
end

def make_chain(length, &block)
  chain = Fiber.new(&block)

  (length - 1).times do
    chain = make_link(chain)
  end

  return chain
end

def run_benchmark(length, repeats, message = :hello)
  chain = nil

  chain = make_chain(length) do
    while true
      Fiber.yield(message)
    end
  end

  repeats.times do
    abort "invalid result" unless chain.resume == message
  end
end

n = (ARGV[0] || 1000).to_i
m = (ARGV[1] || 1000).to_i

5.times do
  run_benchmark(n, m)
end
