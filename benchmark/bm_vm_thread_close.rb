1000.times { Thread.new { sleep } }
i = 0
while i<100_000 # benchmark loop 3
  i += 1
  IO.pipe.each(&:close)
end
