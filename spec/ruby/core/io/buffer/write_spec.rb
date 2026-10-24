require_relative '../../../spec_helper'

describe "IO::Buffer#write" do
  before :each do
    @path = tmp("io_buffer_write.txt")

    @file = File.open(@path, "wb+")
    @buffer = IO::Buffer.new(5)
    @buffer.set_string("Hello")
  end

  after :each do
    @buffer&.free
    @buffer = nil
    @file&.close
    @file = nil
    rm_r @path
  end

  it "writes the whole buffer when no length is given" do
    @buffer.write(@file).should == 5

    @file.rewind
    @file.read.should == "Hello"
  end

  ruby_version_is ""..."4.1" do
    it "writes only the given length, starting at the given offset" do
      @buffer.write(@file, 4, 1).should == 4

      @file.rewind
      @file.read.should == "ello"
    end
  end
  ruby_version_is "4.1" do
    it "writes only the given length, starting at the given offset" do
      @buffer.write(@file, 1, 4).should == 4

      @file.rewind
      @file.read.should == "ello"
    end
  end

  ruby_version_is ""..."4.1" do
    it "writes as much as fits in the buffer when length is 0" do
      @buffer.write(@file, 0).should == 5

      @file.rewind
      @file.read.should == "Hello"
    end
  end
  ruby_version_is "4.1" do
    it "writes 0 bytes when length is 0" do
      @buffer.write(@file, 0, 0).should == 0

      @file.rewind
      @file.read.should == ""
    end
  end

  ruby_version_is ""..."4.1" do
    it "writes from offset to the end of the buffer when length is 0 and offset is given" do
      @buffer.write(@file, 0, 1).should == 4

      @file.rewind
      @file.read.should == "ello"
    end
  end
  ruby_version_is "4.1" do
    it "writes 0 bytes when length is 0 and offset is given" do
      @buffer.write(@file, 1, 0).should == 0

      @file.rewind
      @file.read.should == ""
    end
  end
end
