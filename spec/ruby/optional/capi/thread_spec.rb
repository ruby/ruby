require_relative 'spec_helper'
require_relative '../../core/thread/shared/wakeup'

load_extension("thread")

class Thread
  def self.capi_thread_specs=(t)
    @@capi_thread_specs = t
  end

  def call_capi_rb_thread_wakeup
    @@capi_thread_specs.rb_thread_wakeup(self)
  end
end

describe "C-API Thread function" do
  before :each do
    @t = CApiThreadSpecs.new
    ScratchPad.clear
    Thread.capi_thread_specs = @t
  end

  describe "rb_thread_wait_for" do
    it "sleeps the current thread for the give amount of time" do
      start = Time.now
      @t.rb_thread_wait_for(0, 100_000)
      (Time.now - start).should be_close(0.1, TIME_TOLERANCE)
    end
  end

  describe "rb_thread_alone" do
    it "returns true if there is only one thread" do
      pred = Thread.list.size == 1
      @t.rb_thread_alone.should == pred
    end
  end

  describe "rb_thread_current" do
    it "equals Thread.current" do
      @t.rb_thread_current.should == Thread.current
    end
  end

  describe "rb_thread_local_aref" do
    it "returns the value of a thread-local variable" do
      thr = Thread.current
      sym = :thread_capi_specs_aref
      thr[sym] = 1
      @t.rb_thread_local_aref(thr, sym).should == 1
    end

    it "returns nil if the value has not been set" do
      @t.rb_thread_local_aref(Thread.current, :thread_capi_specs_undefined).should be_nil
    end
  end

  describe "rb_thread_local_aset" do
    it "sets the value of a thread-local variable" do
      thr = Thread.current
      sym = :thread_capi_specs_aset
      @t.rb_thread_local_aset(thr, sym, 2).should == 2
      thr[sym].should == 2
    end
  end

  describe "rb_thread_wakeup" do
    it_behaves_like :thread_wakeup, :call_capi_rb_thread_wakeup
  end

  describe "rb_thread_create" do
    it "creates a new thread" do
      obj = Object.new
      proc = -> x { ScratchPad.record x }
      thr = @t.rb_thread_create(proc, obj)
      thr.should be_kind_of(Thread)
      thr.join
      ScratchPad.recorded.should == obj
    end

    it "handles throwing an exception in the thread" do
      prc = -> x {
        Thread.current.report_on_exception = false
        raise "my error"
      }
      thr = @t.rb_thread_create(prc, nil)
      thr.should be_kind_of(Thread)

      -> {
        thr.join
      }.should raise_error(RuntimeError, "my error")
    end

    it "sets the thread's group" do
      thr = @t.rb_thread_create(-> x { }, nil)
      begin
        thread_group = thr.group
        thread_group.should be_an_instance_of(ThreadGroup)
      ensure
        thr.join
      end
    end
  end

  describe "rb_thread_call_without_gvl" do
    it "runs a C function with the global lock unlocked" do
      thr = Thread.new do
        @t.rb_thread_call_without_gvl
      end

      # Wait until it's blocking...
      Thread.pass while thr.status and thr.status != "sleep"

      # The thread status is set to sleep by rb_thread_call_without_gvl(),
      # but the thread might not be in the blocking read(2) yet, so wait a bit.
      sleep 0.1

      # Wake it up, causing the unblock function to be run.
      thr.wakeup

      # Make sure it stopped and we got a proper value
      thr.value.should be_true
    end

    guard -> { platform_is :mingw and ruby_version_is ""..."2.7" } do
      it "runs a C function with the global lock unlocked and unlocks IO with the generic RUBY_UBF_IO" do
        thr = Thread.new do
          @t.rb_thread_call_without_gvl_with_ubf_io
        end

        # Wait until it's blocking...
        Thread.pass while thr.status and thr.status != "sleep"

        # The thread status is set to sleep by rb_thread_call_without_gvl(),
        # but the thread might not be in the blocking read(2) yet, so wait a bit.
        sleep 0.1

        # Wake it up, causing the unblock function to be run.
        thr.wakeup

        # Make sure it stopped and we got a proper value
        thr.value.should be_true
      end
    end
  end
end
