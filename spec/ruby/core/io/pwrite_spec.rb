# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

guard -> { platform_is_not :windows or ruby_version_is "3.3" } do
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

    it "calls #to_s on the object to be written" do
      object = mock("to_s")
      object.should_receive(:to_s).and_return("foo")
      @file.pwrite(object, 0)
      @file.pread(3, 0).should == "foo"
    end

    it "calls #to_int on the offset" do
      offset = mock("to_int")
      offset.should_receive(:to_int).and_return(2)
      @file.pwrite("foo", offset)
      @file.pread(3, 2).should == "foo"
    end

    it "raises IOError when file is not open in write mode" do
      File.open(@fname, "r") do |file|
        -> { file.pwrite("foo", 1) }.should raise_error(IOError, "not opened for writing")
      end
    end

    it "raises IOError when file is closed" do
      file = File.open(@fname, "w+")
      file.close
      -> { file.pwrite("foo", 1) }.should raise_error(IOError, "closed stream")
    end

    it "raises a NoMethodError if object does not respond to #to_s" do
      -> {
        @file.pwrite(BasicObject.new, 0)
      }.should raise_error(NoMethodError, /undefined method [`']to_s'/)
    end

    it "raises a TypeError if the offset cannot be converted to an Integer" do
      -> {
        @file.pwrite("foo", Object.new)
      }.should raise_error(TypeError, "no implicit conversion of Object into Integer")
    end
  end
end
