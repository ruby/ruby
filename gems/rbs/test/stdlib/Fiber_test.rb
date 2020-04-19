require_relative "test_helper"

class FiberTest < StdlibTest
  target Fiber
  using hook.refinement

  def test_initialize
    Fiber.new {}
  end

  def test_resume_and_yield
    f = Fiber.new { Fiber.yield(1); Fiber.yield('2', :foo) }
    f.resume(1)
    f.resume('2', :foo)
    f.resume
  end
end
