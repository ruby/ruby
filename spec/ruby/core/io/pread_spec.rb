# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

guard -> { platform_is_not :windows or ruby_version_is "3.3" } do
  describe "IO#pread" do
    before :each do
      @fname = tmp("io_pread.txt")
      @contents = "1234567890"
      touch(@fname) { |f| f.write @contents }
      @file = File.open(@fname, "r+")
    end

    after :each do
      @file.close
      rm_r @fname
    end

    it "accepts a length, and an offset" do
      @file.pread(4, 0).should == "1234"
      @file.pread(3, 4).should == "567"
    end

    it "accepts a length, an offset, and an output buffer" do
      buffer = "foo"
      @file.pread(3, 4, buffer)
      buffer.should == "567"
    end

    it "shrinks the buffer in case of less bytes read" do
      buffer = "foo"
      @file.pread(1, 0, buffer)
      buffer.should == "1"
    end

    it "grows the buffer in case of more bytes read" do
      buffer = "foo"
      @file.pread(5, 0, buffer)
      buffer.should == "12345"
    end

    it "does not advance the file pointer" do
      @file.pread(4, 0).should == "1234"
      @file.read.should == "1234567890"
    end

    it "ignores the current offset" do
      @file.pos = 3
      @file.pread(4, 0).should == "1234"
    end

    it "returns an empty string for maxlen = 0" do
      @file.pread(0, 4).should == ""
    end

    it "ignores the offset for maxlen = 0, even if it is out of file bounds" do
      @file.pread(0, 400).should == ""
    end

    it "does not reset the buffer when reading with maxlen = 0" do
      buffer = "foo"
      @file.pread(0, 4, buffer)
      buffer.should == "foo"

      @file.pread(0, 400, buffer)
      buffer.should == "foo"
    end

    it "converts maxlen to Integer using #to_int" do
      maxlen = mock('maxlen')
      maxlen.should_receive(:to_int).and_return(4)
      @file.pread(maxlen, 0).should == "1234"
    end

    it "converts offset to Integer using #to_int" do
      offset = mock('offset')
      offset.should_receive(:to_int).and_return(0)
      @file.pread(4, offset).should == "1234"
    end

    it "converts a buffer to String using to_str" do
      buffer = mock('buffer')
      buffer.should_receive(:to_str).at_least(1).and_return("foo")
      @file.pread(4, 0, buffer)
      buffer.should_not.is_a?(String)
      buffer.to_str.should == "1234"
    end

    it "raises TypeError if maxlen is not an Integer and cannot be coerced into Integer" do
      maxlen = Object.new
      -> { @file.pread(maxlen, 0) }.should raise_error(TypeError, 'no implicit conversion of Object into Integer')
    end

    it "raises TypeError if offset is not an Integer and cannot be coerced into Integer" do
      offset = Object.new
      -> { @file.pread(4, offset) }.should raise_error(TypeError, 'no implicit conversion of Object into Integer')
    end

    it "raises ArgumentError for negative values of maxlen" do
      -> { @file.pread(-4, 0) }.should raise_error(ArgumentError, 'negative string size (or size too big)')
    end

    it "raised Errno::EINVAL for negative values of offset" do
      -> { @file.pread(4, -1) }.should raise_error(Errno::EINVAL, /Invalid argument/)
    end

    it "raises TypeError if the buffer is not a String and cannot be coerced into String" do
      buffer = Object.new
      -> { @file.pread(4, 0, buffer) }.should raise_error(TypeError, 'no implicit conversion of Object into String')
    end

    it "raises EOFError if end-of-file is reached" do
      -> { @file.pread(1, 10) }.should raise_error(EOFError)
    end

    it "raises IOError when file is not open in read mode" do
      File.open(@fname, "w") do |file|
        -> { file.pread(1, 1) }.should raise_error(IOError)
      end
    end

    it "raises IOError when file is closed" do
      file = File.open(@fname, "r+")
      file.close
      -> { file.pread(1, 1) }.should raise_error(IOError)
    end
  end
end
