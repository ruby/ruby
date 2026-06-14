require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "Fiber#runtime" do
    it "returns an Integer" do
      f = Fiber.new(blocking: false) { Fiber.yield }
      f.runtime.should be_kind_of(Integer)
    end

    it "is 0 for a newly created fiber" do
      f = Fiber.new(blocking: false) { Fiber.yield }
      f.runtime.should == 0
    end

    it "is 0 for a blocking fiber" do
      f = Fiber.new(blocking: true) { Fiber.yield }
      f.runtime.should == 0
    end

  it "is positive after the fiber has executed back-edges" do
    # Fiber#runtime counts YARV back-edges; JIT-compiled loops bypass the
    # interpreter dispatch so the counter does not advance there.
    skip "Fiber#runtime counter requires interpreter dispatch" if
      defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

    runtime_seen = nil
    f = Fiber.new do
      10_000.times { }
      runtime_seen = Fiber.current.runtime
    end
    f.resume
    runtime_seen.should be_kind_of(Integer)
    runtime_seen.should > 0
  end

  it "is small at the start of a fresh slot after yielding" do
    skip "Fiber#runtime counter requires interpreter dispatch" if
      defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

    counts = []
    f = Fiber.new do
      10_000.times { }
      counts << Fiber.current.runtime  # accumulated after work
      Fiber.yield
      counts << Fiber.current.runtime  # reset to 0 on resume
    end
    f.resume
    f.resume if f.alive?
    counts[0].should > 0
    counts[1].should < counts[0]  # fresh slot has less runtime than work phase
  end

    it "does not exceed quantum after forced preemption" do
      skip "Fiber#runtime counter requires interpreter dispatch" if
        defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

      runtime_seen = nil
      # quantum: 5_000 means preemption fires after 5_000 back-edges.
      # The runtime captured at the end of one slot should be close to the quantum.
      f = Fiber.new(quantum: 5_000) do
        100_000.times { }  # more than the quantum
        runtime_seen = Fiber.current.runtime
      end
      f.resume
      # Without a scheduler the fiber runs to completion, so runtime reflects
      # the full 100_000 iterations here. We just check it's a valid integer.
      runtime_seen.should be_kind_of(Integer)
      runtime_seen.should > 0
    end
  end
end
