require_relative '../../spec_helper'
require 'getoptlong'

describe "GetoptLong#terminated?" do
  it "returns true if option processing has terminated" do
    argv [ "--size", "10k" ] do
      opts = GetoptLong.new(["--size", GetoptLong::REQUIRED_ARGUMENT])
      opts.terminated?.should == false

      opts.get.should == ["--size", "10k"]
      opts.terminated?.should == false

      opts.get.should == nil
      opts.terminated?.should == true
    end
  end
end
