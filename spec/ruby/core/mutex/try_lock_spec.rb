require_relative '../../spec_helper'

describe "Mutex#try_lock" do
  describe "when unlocked" do
    it "returns true" do
      m = Mutex.new
      m.try_lock.should == true
    end

    it "locks the mutex" do
      m = Mutex.new
      m.try_lock
      m.locked?.should == true
    end
  end

  describe "when locked by the current thread" do
    it "returns false" do
      m = Mutex.new
      m.lock
      m.try_lock.should == false
    end
  end

  describe "when locked by another thread" do
    it "returns false" do
      m = Mutex.new
      m.lock
      Thread.new { m.try_lock }.value.should == false
    end
  end
end
