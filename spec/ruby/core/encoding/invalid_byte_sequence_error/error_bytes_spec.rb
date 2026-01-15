# encoding: binary
require_relative "../../../spec_helper"
require_relative '../fixtures/classes'

describe "Encoding::InvalidByteSequenceError#error_bytes" do
  before :each do
    @exception, @errinfo = EncodingSpecs::InvalidByteSequenceError.exception
    @exception2, @errinfo2 = EncodingSpecs::InvalidByteSequenceErrorIndirect.exception
  end

  it "returns a String" do
    @exception.error_bytes.should be_an_instance_of(String)
    @exception2.error_bytes.should be_an_instance_of(String)
  end

  it "returns the bytes that caused the exception" do
    @exception.error_bytes.size.should == 1
    @exception.error_bytes.should == "\xF1"
    @exception.error_bytes.should == @errinfo[-2]

    @exception2.error_bytes.size.should == 1
    @exception2.error_bytes.should == "\xA1"
    @exception2.error_bytes.should == @errinfo2[-2]
  end

  it "uses BINARY as the encoding" do
    @exception.error_bytes.encoding.should == Encoding::BINARY

    @exception2.error_bytes.encoding.should == Encoding::BINARY
  end
end
