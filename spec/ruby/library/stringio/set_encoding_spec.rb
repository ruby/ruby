require 'stringio'
require_relative '../../spec_helper'

describe "StringIO#set_encoding" do
  it "sets the encoding of the underlying String if the String is not frozen" do
    str = "".encode(Encoding::US_ASCII)

    io = StringIO.new(str)
    io.set_encoding Encoding::UTF_8
    io.string.encoding.should == Encoding::UTF_8
  end

  it "does not set the encoding of the underlying String if the String is frozen" do
    str = "".encode(Encoding::US_ASCII).freeze

    io = StringIO.new(str)
    io.set_encoding Encoding::UTF_8
    io.string.encoding.should == Encoding::US_ASCII
  end
end
