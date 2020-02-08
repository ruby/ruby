# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

platform_is_not :windows do
  describe "IO#pwrite" do
    before :each do
      @fname = tmp("io_pwrite.txt")
      @file = File.open(@fname, "w+")
    end

    after :each do
      @file.close
      rm_r @fname
    end

    it "returns the number of bytes written" do
      @file.pwrite("foo", 0).should == 3
    end

    it "accepts a string and an offset"  do
      @file.pwrite("foo", 2)
      @file.pread(3, 2).should == "foo"
    end

    it "does not advance the pointer in the file" do
      @file.pwrite("bar", 3)
      @file.write("foo")
      @file.pread(6, 0).should == "foobar"
    end

    it "raises IOError when file is not open in write mode" do
      File.open(@fname, "r") do |file|
        -> { file.pwrite("foo", 1) }.should raise_error(IOError)
      end
    end

    it "raises IOError when file is closed" do
      file = File.open(@fname, "w+")
      file.close
      -> { file.pwrite("foo", 1) }.should raise_error(IOError)
    end
  end
end
