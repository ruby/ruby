require_relative '../../spec_helper'
require "zlib"

describe "Zlib.inflate" do
  it "inflates some data" do
    Zlib.inflate([120, 156, 51, 52, 132, 1, 0, 10, 145, 1, 235].pack('C*')).should == "1" * 10
  end
end
