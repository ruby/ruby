require_relative '../../spec_helper'

require 'io/wait'

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
end
