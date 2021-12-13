require_relative '../../spec_helper'
require_relative 'shared/blocking'

ruby_version_is "3.0" do
  require "fiber"

  describe "Fiber.blocking?" do
    it_behaves_like :non_blocking_fiber, -> { Fiber.blocking? }

    context "when fiber is blocking" do
      context "root Fiber of the main thread" do
        it "returns 1 for blocking: true" do
          fiber = Fiber.new(blocking: true) { Fiber.blocking? }
          blocking = fiber.resume

          blocking.should == 1
        end
      end

      context "root Fiber of a new thread" do
        it "returns 1 for blocking: true" do
          thread = Thread.new do
            fiber = Fiber.new(blocking: true) { Fiber.blocking? }
            blocking = fiber.resume

            blocking.should == 1
          end

          thread.join
        end
      end
    end
  end

  describe "Fiber#blocking?" do
    it_behaves_like :non_blocking_fiber, -> { Fiber.current.blocking? }

    context "when fiber is blocking" do
      context "root Fiber of the main thread" do
        it "returns true for blocking: true" do
          fiber = Fiber.new(blocking: true) { Fiber.current.blocking? }
          blocking = fiber.resume

          blocking.should == true
        end
      end

      context "root Fiber of a new thread" do
        it "returns true for blocking: true" do
          thread = Thread.new do
            fiber = Fiber.new(blocking: true) { Fiber.current.blocking? }
            blocking = fiber.resume

            blocking.should == true
          end

          thread.join
        end
      end
    end
  end
end
