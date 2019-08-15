require 'stringio'
require_relative '../../spec_helper'

describe "StringIO#internal_encoding" do
  it "returns nil" do
    io = StringIO.new
    io.set_encoding Encoding::UTF_8
    io.internal_encoding.should == nil
  end
end
