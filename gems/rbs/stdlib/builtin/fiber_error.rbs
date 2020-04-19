# Raised when an invalid operation is attempted on a
# [Fiber](https://ruby-doc.org/core-2.6.3/Fiber.html), in particular when
# attempting to call/resume a dead fiber, attempting to yield from the
# root fiber, or calling a fiber across threads.
# 
# ```ruby
# fiber = Fiber.new{}
# fiber.resume #=> nil
# fiber.resume #=> FiberError: dead fiber called
# ```
class FiberError < StandardError
end
