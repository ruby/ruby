require_relative '../../spec_helper'
require 'fiber'

describe "Fiber#inspect" do
  describe "status" do
    it "is resumed for the root Fiber of a Thread" do
      inspected = Thread.new { Fiber.current.inspect }.value
      inspected.should =~ /\A#<Fiber:0x\h+ .*\(resumed\)>\z/
    end

    it "is created for a Fiber which did not run yet" do
      inspected = Fiber.new {}.inspect
      inspected.should =~ /\A#<Fiber:0x\h+ .+ \(created\)>\z/
    end

    it "is resumed for a Fiber which was resumed" do
      inspected = Fiber.new { Fiber.current.inspect }.resume
      inspected.should =~ /\A#<Fiber:0x\h+ .+ \(resumed\)>\z/
    end

    it "is resumed for a Fiber which was transferred" do
      inspected = Fiber.new { Fiber.current.inspect }.transfer
      inspected.should =~ /\A#<Fiber:0x\h+ .+ \(resumed\)>\z/
    end

    it "is suspended for a Fiber which was resumed and yielded" do
      inspected = Fiber.new { Fiber.yield }.tap(&:resume).inspect
      inspected.should =~ /\A#<Fiber:0x\h+ .+ \(suspended\)>\z/
    end

    it "is terminated for a Fiber which has terminated" do
      inspected = Fiber.new {}.tap(&:resume).inspect
      inspected.should =~ /\A#<Fiber:0x\h+ .+ \(terminated\)>\z/
    end
  end
end
