require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#value" do
  it "returns the result of the block" do
    Thread.new { 3 }.value.should == 3
  end

  it "re-raises an error for an uncaught exception" do
    t = Thread.new {
      Thread.current.report_on_exception = false
      raise "Hello"
    }
    -> { t.value }.should raise_error(RuntimeError, "Hello")
  end

  it "is nil for a killed thread" do
    t = Thread.new { Thread.current.exit }
    t.value.should == nil
  end

  it "returns when the thread finished" do
    q = Queue.new
    t = Thread.new {
      q.pop
    }
    -> { t.value }.should block_caller
    q.push :result
    t.value.should == :result
  end
end
