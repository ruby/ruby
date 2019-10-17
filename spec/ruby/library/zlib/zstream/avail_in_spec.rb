require_relative '../../../spec_helper'
require 'zlib'

describe "Zlib::ZStream#avail_in" do
  it "returns bytes in the input buffer" do
    z = Zlib::Deflate.new
    z.avail_in.should == 0
  end
end
