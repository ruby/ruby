show_limit %q{
  fibers = []
  begin
    fiber = Fiber.new{Fiber.yield}
    fiber.resume
    fibers << fiber

    raise Exception, "skipping" if fibers.count >= 10_000
  rescue Exception => error
    puts "Fiber count: #{fibers.count} (#{error})"
    break
  end while true
}

assert_equal %q{ok}, %q{
  Fiber.new{
  }.resume
  :ok
}

assert_equal %q{ok}, %q{
  100.times.collect{Fiber.new{}}
  :ok
}

assert_equal %q{ok}, %q{
  fibers = 1000.times.collect{Fiber.new{Fiber.yield}}
  fibers.each(&:resume)
  fibers.each(&:resume)
  :ok
}

assert_normal_exit %q{
  at_exit { Fiber.new{}.resume }
}

assert_normal_exit %q{
  Fiber.new(&Object.method(:class_eval)).resume("foo")
}, '[ruby-dev:34128]'

# [Bug #21400]
assert_normal_exit %q{
  Thread.new { Fiber.current.kill }.join
}

# fiber_current() must not read a stale (cached) TLS execution context after a
# fiber's coroutine migrates between native threads under the M:N scheduler.
# Needs >= 2 Ractors so coroutines actually migrate; sleep drives the migration.
assert_equal 'ok', %q{
  Warning[:experimental] = false
  2.times.map do
    Ractor.new do
      200.times do
        f = Fiber.new { Fiber.yield; 1 }
        f.resume
        sleep(0.0003)   # block -> M:N native-thread migration
        f.resume rescue nil
      end
      :ok
    end
  end.each(&:value)
  :ok
}
