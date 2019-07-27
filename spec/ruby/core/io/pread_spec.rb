# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

ruby_version_is "2.5" do
  platform_is_not :windows do
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

      it "does not advance the file pointer" do
        @file.pread(4, 0).should == "1234"
        @file.read.should == "1234567890"
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
end
