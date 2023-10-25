require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#join" do
  it "returns the thread when it is finished" do
    t = Thread.new {}
    t.join.should equal(t)
  end

  it "returns the thread when it is finished when given a timeout" do
    t = Thread.new {}
    t.join
    t.join(0).should equal(t)
  end

  it "coerces timeout to a Float if it is not nil" do
    t = Thread.new {}
    t.join
    t.join(0).should equal(t)
    t.join(0.0).should equal(t)
    t.join(nil).should equal(t)
  end

  it "raises TypeError if the argument is not a valid timeout" do
    t = Thread.new { }
    t.join
    -> { t.join(:foo) }.should raise_error TypeError
    -> { t.join("bar") }.should raise_error TypeError
  end

  it "returns nil if it is not finished when given a timeout" do
    q = Queue.new
    t = Thread.new { q.pop }
    begin
      t.join(0).should == nil
    ensure
      q << true
    end
    t.join.should == t
  end

  it "accepts a floating point timeout length" do
    q = Queue.new
    t = Thread.new { q.pop }
    begin
      t.join(0.01).should == nil
    ensure
      q << true
    end
    t.join.should == t
  end

  it "raises any exceptions encountered in the thread body" do
    t = Thread.new {
      Thread.current.report_on_exception = false
      raise NotImplementedError.new("Just kidding")
    }
    -> { t.join }.should raise_error(NotImplementedError)
  end

  it "returns the dead thread" do
    t = Thread.new { Thread.current.kill }
    t.join.should equal(t)
  end

  it "raises any uncaught exception encountered in ensure block" do
    t = ThreadSpecs.dying_thread_ensures { raise NotImplementedError.new("Just kidding") }
    -> { t.join }.should raise_error(NotImplementedError)
  end
end
