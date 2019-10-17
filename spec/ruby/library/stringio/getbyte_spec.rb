require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/getc'

describe "StringIO#getbyte" do
  it_behaves_like :stringio_getc, :getbyte

  it "returns the 8-bit byte at the current position" do
    io = StringIO.new("example")

    io.getbyte.should == 101
    io.getbyte.should == 120
    io.getbyte.should ==  97
  end
end

describe "StringIO#getbyte when self is not readable" do
  it_behaves_like :stringio_getc_not_readable, :getbyte
end
