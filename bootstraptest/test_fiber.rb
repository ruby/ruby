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
  10_000.times.collect{Fiber.new{}}
  :ok
}

assert_equal %q{ok}, %q{
  fibers = 100.times.collect{Fiber.new{Fiber.yield}}
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
