require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/readchar'

describe "StringIO#readbyte" do
  it_behaves_like :stringio_readchar, :readbyte

  it "reads the next 8-bit byte from self's current position" do
    io = StringIO.new("example")

    io.readbyte.should == 101

    io.pos = 4
    io.readbyte.should == 112
  end
end

describe "StringIO#readbyte when self is not readable" do
  it_behaves_like :stringio_readchar_not_readable, :readbyte
end
