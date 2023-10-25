ready = false
t = Thread.new do
  f = Fiber.new do
    begin
      Fiber.yield
    ensure
      STDERR.puts "suspended fiber ensure"
    end
  end
  f.resume

  begin
    ready = true
    sleep
  ensure
    STDERR.puts "current fiber ensure"
  end
end

Thread.pass until ready && t.stop?

# let the program end, it's the same as #exit or an exception for this behavior
