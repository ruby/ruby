require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#tty?" do
  platform_is_not :windows do
    it "returns true if this stream is a terminal device (TTY)" do
      begin
        # check to enabled tty
        File.open('/dev/tty') {}
      rescue Errno::ENXIO
        skip "workaround for not configured environment like OS X"
      else
        File.open('/dev/tty') { |f| f.tty? }.should == true
      end
    end
  end

  it "returns false if this stream is not a terminal device (TTY)" do
    File.open(__FILE__) { |f| f.tty? }.should == false
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.tty? }.should.raise(IOError)
  end

  it "returns false for stdio streams if they are not connected to a terminal" do
    skip "requires STDOUT and STDERR to be terminal devices" unless STDOUT.tty? && STDERR.tty?
    begin
      io = IO.popen(ruby_cmd('print [STDIN.tty?, STDOUT.tty?, STDERR.tty?].inspect'), "r")
      io.read.should == "[true, false, true]"
    ensure
      io&.close
    end

    begin
      io = IO.popen(ruby_cmd('print [STDIN.tty?, STDOUT.tty?, STDERR.tty?].inspect'), "r+")
      io.read.should == "[false, false, true]"
    ensure
      io&.close
    end
  end
end
