require_relative '../../spec_helper'
require 'zlib'

describe "Zlib.gzip" do
  before :each do
    @data = '12345abcde'
    @zip = [31, 139, 8, 0, 44, 220, 209, 71, 0, 3, 51, 52, 50, 54, 49, 77,
            76, 74, 78, 73, 5, 0, 157, 5, 0, 36, 10, 0, 0, 0].pack('C*')
  end

  it "gzips the given string" do
    # skip gzip header for now
    Zlib.gzip(@data)[10..-1].should == @zip[10..-1]
  end
end
