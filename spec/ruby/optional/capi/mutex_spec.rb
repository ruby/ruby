require_relative 'spec_helper'

load_extension("mutex")

describe "C-API Mutex functions" do
  before :each do
    @s = CApiMutexSpecs.new
    @m = Mutex.new
  end

  describe "rb_mutex_new" do
    it "creates a new mutex" do
      @s.rb_mutex_new.should.instance_of?(Mutex)
    end
  end

  describe "rb_mutex_locked_p" do
    it "returns false if the mutex is not locked" do
      @s.rb_mutex_locked_p(@m).should == false
    end

    it "returns true if the mutex is locked" do
      @m.lock
      @s.rb_mutex_locked_p(@m).should == true
    end
  end

  describe "rb_mutex_trylock" do
    it "locks the mutex if not locked" do
      @s.rb_mutex_trylock(@m).should == true
      @m.locked?.should == true
    end

    it "returns false if the mutex is already locked" do
      @m.lock
      @s.rb_mutex_trylock(@m).should == false
      @m.locked?.should == true
    end
  end

  describe "rb_mutex_lock" do
    it "returns when the mutex isn't locked" do
      @s.rb_mutex_lock(@m).should == @m
      @m.locked?.should == true
    end

    it "throws an exception when already locked in the same thread" do
      @m.lock
      -> { @s.rb_mutex_lock(@m) }.should.raise(ThreadError)
      @m.locked?.should == true
    end
  end

  describe "rb_mutex_unlock" do
    it "raises an exception when not locked" do
      -> { @s.rb_mutex_unlock(@m) }.should.raise(ThreadError)
      @m.locked?.should == false
    end

    it "unlocks the mutex when locked" do
      @m.lock
      @s.rb_mutex_unlock(@m).should == @m
      @m.locked?.should == false
    end
  end

  describe "rb_mutex_sleep" do
    it "throws an exception when the mutex is not locked" do
      -> { @s.rb_mutex_sleep(@m, 0.1) }.should.raise(ThreadError)
      @m.locked?.should == false
    end

    it "sleeps when the mutex is locked" do
      @m.lock
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @s.rb_mutex_sleep(@m, 0.001)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (t2 - t1).should >= 0
      @m.locked?.should == true
    end
  end

  describe "rb_mutex_synchronize" do
    it "calls the function while the mutex is locked" do
      callback = -> { @m.locked?.should == true }
      @s.rb_mutex_synchronize(@m, callback)
    end

    it "returns a value returned from a callback" do
      callback = -> { :foo }
      @s.rb_mutex_synchronize(@m, callback).should == :foo
    end

    it "calls a C-function that accepts and returns non-VALUE values" do
      @s.rb_mutex_synchronize_with_naughty_callback(@m).should == 42
    end

    it "calls a native function" do
      @s.rb_mutex_synchronize_with_native_callback(@m, 42).should == 42
    end
  end
end
