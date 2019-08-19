require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread.current" do
  it "returns a thread" do
    current = Thread.current
    current.should be_kind_of(Thread)
  end

  it "returns the current thread" do
    t = Thread.new { Thread.current }
    t.value.should equal(t)
    Thread.current.should_not equal(t.value)
  end

  it "returns the correct thread in a Fiber" do
    # This catches a bug where Fibers are running on a thread-pool
    # and Fibers from a different Ruby Thread reuse the same native thread.
    # Caching the Ruby Thread based on the native thread is not correct in that case.
    2.times do
      t = Thread.new {
        cur = Thread.current
        Fiber.new {
          Thread.current
        }.resume.should equal cur
        cur
      }
      t.value.should equal t
    end
  end
end
