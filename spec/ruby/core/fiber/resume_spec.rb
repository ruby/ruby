require_relative '../../spec_helper'
require_relative '../../shared/fiber/resume'

with_feature :fiber do
  describe "Fiber#resume" do
    it_behaves_like :fiber_resume, :resume
  end

  describe "Fiber#resume" do
    it "raises a FiberError if the Fiber tries to resume itself" do
      fiber = Fiber.new { fiber.resume }
      -> { fiber.resume }.should raise_error(FiberError, /double resume/)
    end

    it "returns control to the calling Fiber if called from one" do
      fiber1 = Fiber.new { :fiber1 }
      fiber2 = Fiber.new { fiber1.resume; :fiber2 }
      fiber2.resume.should == :fiber2
    end

    with_feature :fork do
      # Redmine #595
      it "executes the ensure clause" do
        rd, wr = IO.pipe

        pid = Kernel::fork do
          rd.close
          f = Fiber.new do
            begin
              Fiber.yield
            ensure
              wr.write "executed"
            end
          end

          # The apparent issue is that when Fiber.yield executes, control
          # "leaves" the "ensure block" and so the ensure clause should run. But
          # control really does NOT leave the ensure block when Fiber.yield
          # executes. It merely pauses there. To require ensure to run when a
          # Fiber is suspended then makes ensure-in-a-Fiber-context different
          # than ensure-in-a-Thread-context and this would be very confusing.
          f.resume

          # When we execute the second #resume call, the ensure block DOES exit,
          # the ensure clause runs.
          f.resume

          exit 0
        end

        wr.close
        Process.waitpid pid

        rd.read.should == "executed"
        rd.close
      end
    end
  end
end
