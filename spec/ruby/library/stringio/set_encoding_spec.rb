require 'stringio'
require_relative '../../spec_helper'

describe "StringIO#set_encoding" do
  it "sets the encoding of the underlying String" do
    io = StringIO.new
    io.set_encoding Encoding::UTF_8
    io.string.encoding.should == Encoding::UTF_8
  end
end
