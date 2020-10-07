require_relative 'scheduler'

scheduler = Scheduler.new
Thread.current.scheduler = scheduler

ary = []
Fiber.schedule do
  p [:scheduled_fiber, Fiber.current]
  f = Fiber.new(blocking: false) do # blocking: false is just to simulate "all Fibers are non-blocking"
    Fiber.yield 1
    sleep 0.1
    Fiber.yield 2
    sleep 0.2
    :last
  end
  ary << p(f.resume)
  ary << p(f.resume)
  ary << p(f.resume)
end

scheduler.run

p ary # [1, nil, 2] but should be [1, 2, :last]
