require_relative '../../spec_helper'
require "zlib"

describe "Zlib.deflate" do
  it "deflates some data" do
    Zlib.deflate("1" * 10).should == [120, 156, 51, 52, 132, 1, 0, 10, 145, 1, 235].pack('C*')
  end
end
