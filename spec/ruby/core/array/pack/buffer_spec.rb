# encoding: binary

require_relative '../../../spec_helper'

describe "Array#pack with :buffer option" do
  it "returns specified buffer" do
    n = [ 65, 66, 67 ]
    buffer = " "*3
    result = n.pack("ccc", buffer: buffer)      #=> "ABC"
    result.should equal(buffer)
  end

  it "adds result at the end of buffer content" do
    n = [ 65, 66, 67 ] # result without buffer is "ABC"

    buffer = ""
    n.pack("ccc", buffer: buffer).should == "ABC"

    buffer = "123"
    n.pack("ccc", buffer: buffer).should == "123ABC"

    buffer = "12345"
    n.pack("ccc", buffer: buffer).should == "12345ABC"
  end

  it "raises TypeError exception if buffer is not String" do
    -> { [65].pack("ccc", buffer: []) }.should raise_error(
      TypeError, "buffer must be String, not Array")
  end

  context "offset (@) is specified" do
    it 'keeps buffer content if it is longer than offset' do
      n = [ 65, 66, 67 ]
      buffer = "123456"
      n.pack("@3ccc", buffer: buffer).should == "123ABC"
    end

    it "fills the gap with \\0 if buffer content is shorter than offset" do
      n = [ 65, 66, 67 ]
      buffer = "123"
      n.pack("@6ccc", buffer: buffer).should == "123\0\0\0ABC"
    end

    it 'does not keep buffer content if it is longer than offset + result' do
      n = [ 65, 66, 67 ]
      buffer = "1234567890"
      n.pack("@3ccc", buffer: buffer).should == "123ABC"
    end
  end
end
