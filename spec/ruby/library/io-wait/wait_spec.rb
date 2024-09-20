require_relative '../../spec_helper'
require_relative '../../fixtures/io'

ruby_version_is ''...'3.2' do
  require 'io/wait'
end

describe "IO#wait" do
  before :each do
    @io = File.new(__FILE__ )

    if /mswin|mingw/ =~ RUBY_PLATFORM
      require 'socket'
      @r, @w = Socket.pair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    else
      @r, @w = IO.pipe
    end
  end

  after :each do
    @io.close unless @io.closed?

    @r.close unless @r.closed?
    @w.close unless @w.closed?
  end

  context "[events, timeout] passed" do
    ruby_version_is ""..."3.2" do
      it "returns self when the READABLE event is ready during the timeout" do
        @w.write('data to read')
        @r.wait(IO::READABLE, 2).should.equal?(@r)
      end

      it "returns self when the WRITABLE event is ready during the timeout" do
        @w.wait(IO::WRITABLE, 0).should.equal?(@w)
      end
    end

    ruby_version_is "3.2" do
      it "returns events mask when the READABLE event is ready during the timeout" do
        @w.write('data to read')
        @r.wait(IO::READABLE, 2).should == IO::READABLE
      end

      it "returns events mask when the WRITABLE event is ready during the timeout" do
        @w.wait(IO::WRITABLE, 0).should == IO::WRITABLE
      end
    end

    it "waits for the READABLE event to be ready" do
      @r.wait(IO::READABLE, 0).should == nil

      @w.write('data to read')
      @r.wait(IO::READABLE, 0).should_not == nil
    end

    it "waits for the WRITABLE event to be ready" do
      written_bytes = IOSpec.exhaust_write_buffer(@w)
      @w.wait(IO::WRITABLE, 0).should == nil

      @r.read(written_bytes)
      @w.wait(IO::WRITABLE, 0).should_not == nil
    end

    it "returns nil when the READABLE event is not ready during the timeout" do
      @w.wait(IO::READABLE, 0).should == nil
    end

    it "returns nil when the WRITABLE event is not ready during the timeout" do
      IOSpec.exhaust_write_buffer(@w)
      @w.wait(IO::WRITABLE, 0).should == nil
    end

    it "raises IOError when io is closed (closed stream (IOError))" do
      @io.close
      -> { @io.wait(IO::READABLE, 0) }.should raise_error(IOError, "closed stream")
    end

    ruby_version_is "3.2" do
      it "raises ArgumentError when events is not positive" do
        -> { @w.wait(0, 0) }.should raise_error(ArgumentError, "Events must be positive integer!")
        -> { @w.wait(-1, 0) }.should raise_error(ArgumentError, "Events must be positive integer!")
      end
    end

    it "changes thread status to 'sleep' when waits for READABLE event" do
      t = Thread.new { @r.wait(IO::READABLE, 10) }
      sleep 1
      t.status.should == 'sleep'
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end
    end

    it "changes thread status to 'sleep' when waits for WRITABLE event" do
      IOSpec.exhaust_write_buffer(@w)

      t = Thread.new { @w.wait(IO::WRITABLE, 10) }
      sleep 1
      t.status.should == 'sleep'
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end
    end

    it "can be interrupted when waiting for READABLE event" do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      t = Thread.new do
        @r.wait(IO::READABLE, 10)
      end

      Thread.pass until t.stop?
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end

      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (finish - start).should < 9
    end

    it "can be interrupted when waiting for WRITABLE event" do
      IOSpec.exhaust_write_buffer(@w)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      t = Thread.new do
        @w.wait(IO::WRITABLE, 10)
      end

      Thread.pass until t.stop?
      t.kill
      t.join # Thread#kill doesn't wait for the thread to end

      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (finish - start).should < 9
    end
  end

  context "[timeout, mode] passed" do
    it "accepts :r, :read, :readable mode to check READABLE event" do
      @io.wait(0, :r).should == @io
      @io.wait(0, :read).should == @io
      @io.wait(0, :readable).should == @io
    end

    it "accepts :w, :write, :writable mode to check WRITABLE event" do
      @io.wait(0, :w).should == @io
      @io.wait(0, :write).should == @io
      @io.wait(0, :writable).should == @io
    end

    it "accepts :rw, :read_write, :readable_writable mode to check READABLE and WRITABLE events" do
      @io.wait(0, :rw).should == @io
      @io.wait(0, :read_write).should == @io
      @io.wait(0, :readable_writable).should == @io
    end

    it "accepts a list of modes" do
       @io.wait(0, :r, :w, :rw).should == @io
    end

    # It works at least since 2.7 but by some reason may fail on 3.1
    ruby_version_is "3.2" do
      it "accepts timeout and mode in any order" do
        @io.wait(0, :r).should == @io
        @io.wait(:r, 0).should == @io
        @io.wait(:r, 0, :w).should == @io
      end
    end

    it "raises ArgumentError when passed wrong Symbol value as mode argument" do
      -> { @io.wait(0, :wrong) }.should raise_error(ArgumentError, "unsupported mode: wrong")
    end

    # It works since 3.0 but by some reason may fail on 3.1
    ruby_version_is "3.2" do
      it "raises ArgumentError when several Integer arguments passed" do
        -> { @w.wait(0, 10, :r) }.should raise_error(ArgumentError, "timeout given more than once")
      end
    end

    ruby_version_is "3.2" do
      it "raises IOError when io is closed (closed stream (IOError))" do
        @io.close
        -> { @io.wait(0, :r) }.should raise_error(IOError, "closed stream")
      end
    end
  end
end
