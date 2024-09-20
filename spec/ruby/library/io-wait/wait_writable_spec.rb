require_relative '../../spec_helper'
require_relative '../../fixtures/io'

ruby_version_is ''...'3.2' do
  require 'io/wait'
end

describe "IO#wait_writable" do
  it "waits for the IO to become writable with no timeout" do
    STDOUT.wait_writable.should == STDOUT
  end

  it "waits for the IO to become writable with the given timeout" do
    STDOUT.wait_writable(1).should == STDOUT
  end

  it "waits for the IO to become writable with the given large timeout" do
    # Represents one year and is larger than a 32-bit int
    STDOUT.wait_writable(365 * 24 * 60 * 60).should == STDOUT
  end

  it "can be interrupted" do
    rd, wr = IO.pipe
    IOSpec.exhaust_write_buffer(wr)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    t = Thread.new do
      wr.wait_writable(10)
    end

    Thread.pass until t.stop?
    t.kill
    t.join

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (finish - start).should < 9
  ensure
    rd.close unless rd.closed?
    wr.close unless wr.closed?
  end
end
