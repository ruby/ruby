require_relative '../../spec_helper'

ruby_version_is ''...'3.2' do
  require 'io/wait'
end

describe "IO#wait_readable" do
  before :each do
    @io = File.new(__FILE__ )
  end

  after :each do
    @io.close
  end

  it "waits for the IO to become readable with no timeout" do
    @io.wait_readable.should == @io
  end

  it "waits for the IO to become readable with the given timeout" do
    @io.wait_readable(1).should == @io
  end

  it "waits for the IO to become readable with the given large timeout" do
    @io.wait_readable(365 * 24 * 60 * 60).should == @io
  end

  it "can be interrupted" do
    rd, wr = IO.pipe
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    t = Thread.new do
      rd.wait_readable(10)
    end

    Thread.pass until t.stop?
    t.kill
    t.join

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (finish - start).should < 9
  ensure
    rd.close
    wr.close
  end
end
