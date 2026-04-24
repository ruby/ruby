require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "IO::Buffer#bit_count" do
    it "counts all set bits in the whole buffer" do
      IO::Buffer.for(+"\xFF\x00\x0F") do |buffer|
        buffer.bit_count.should == 12
      end
    end

    it "returns 0 for a buffer of all zero bytes" do
      IO::Buffer.for(+"\x00\x00\x00") do |buffer|
        buffer.bit_count.should == 0
      end
    end

    it "returns 8 * size for a buffer of all 0xFF bytes" do
      IO::Buffer.for(+"\xFF" * 9) do |buffer|
        buffer.bit_count.should == 72
      end
    end

    it "returns 0 for an empty buffer" do
      IO::Buffer.new(0).bit_count.should == 0
    end

    it "accepts an offset to start counting from (length defaults to remaining bytes)" do
      IO::Buffer.for(+"\xFF\x00\x0F") do |buffer|
        buffer.bit_count(0).should == 12  # offset=0 => entire buffer
        buffer.bit_count(1).should == 4   # offset=1 => 0x00 + 0x0F
        buffer.bit_count(2).should == 4   # offset=2 => 0x0F only
      end
    end

    it "accepts an offset and length to restrict the counted region" do
      IO::Buffer.for(+"\xFF\x00\x0F") do |buffer|
        buffer.bit_count(0, 1).should == 8  # just 0xFF
        buffer.bit_count(1, 1).should == 0  # just 0x00
        buffer.bit_count(2, 1).should == 4  # just 0x0F
        buffer.bit_count(1, 2).should == 4  # 0x00 + 0x0F
      end
    end

    it "handles 8-byte aligned buffers efficiently" do
      IO::Buffer.for(+"\xAA" * 8) do |buffer|
        # 0xAA = 10101010 => 4 bits per byte => 32 total
        buffer.bit_count.should == 32
      end
    end

    it "raises ArgumentError when offset + length exceeds buffer size" do
      IO::Buffer.for(+"\xFF") do |buffer|
        -> { buffer.bit_count(0, 2) }.should raise_error(ArgumentError)
        -> { buffer.bit_count(1, 1) }.should raise_error(ArgumentError)
      end
    end

    it "returns an Integer" do
      IO::Buffer.for(+"\xFF") do |buffer|
        buffer.bit_count.should be_kind_of(Integer)
      end
    end
  end
end
