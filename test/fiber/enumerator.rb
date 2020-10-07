require_relative 'scheduler'

def some_yielder
  p [Fiber.current, Thread.current.scheduler, Thread.current.blocking?]
  yield 1
  sleep 0.1
  yield 2
end

def enumerator
  to_enum(:some_yielder)
end

scheduler = Scheduler.new
Thread.current.scheduler = scheduler

ary = []
Fiber.schedule do
  p [:scheduled_fiber, Fiber.current]
  enum = enumerator()
  ary << p(enum.next)
  ary << p(enum.next)
  ary << (enum.next rescue $!)
end

scheduler.run

p ary # should be [1, 2, #<StopIteration: iteration reached an end>]
