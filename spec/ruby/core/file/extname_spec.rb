# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "File.extname" do
  it "returns the extension (the portion of file name in path after the period)" do
    File.extname("foo.rb").should == ".rb"
    File.extname("/foo/bar.rb").should == ".rb"
    File.extname("/foo.rb/bar.c").should == ".c"
    File.extname("bar").should == ""
    File.extname(".bashrc").should == ""
    File.extname("/foo.bar/baz").should == ""
    File.extname(".app.conf").should == ".conf"
  end

  it "returns unfrozen strings" do
    File.extname("foo.rb").frozen?.should == false
    File.extname("/foo/bar.rb").frozen?.should == false
    File.extname("/foo.rb/bar.c").frozen?.should == false
    File.extname("bar").frozen?.should == false
    File.extname(".bashrc").frozen?.should == false
    File.extname("/foo.bar/baz").frozen?.should == false
    File.extname(".app.conf").frozen?.should == false
  end

  it "returns the extension for edge cases" do
    File.extname("").should ==  ""
    File.extname(".").should ==  ""
    File.extname("/").should ==  ""
    File.extname("/.").should ==  ""
    File.extname("..").should ==  ""
    File.extname("...").should ==  ""
    File.extname("....").should ==  ""
  end

  describe "for a filename ending with a dot" do
    guard -> { platform_is :windows or ruby_version_is ""..."2.7" } do
      it "returns ''" do
        File.extname(".foo.").should == ""
        File.extname("foo.").should == ""
      end
    end

    guard -> { platform_is_not :windows and ruby_version_is "2.7" } do
      it "returns '.'" do
        File.extname(".foo.").should == "."
        File.extname("foo.").should == "."
      end
    end
  end

  it "returns only the last extension of a file with several dots" do
    File.extname("a.b.c.d.e").should == ".e"
  end

  it "accepts an object that has a #to_path method" do
    File.extname(mock_to_path("a.b.c.d.e")).should == ".e"
  end

  it "raises a TypeError if not passed a String type" do
    -> { File.extname(nil)   }.should raise_error(TypeError)
    -> { File.extname(0)     }.should raise_error(TypeError)
    -> { File.extname(true)  }.should raise_error(TypeError)
    -> { File.extname(false) }.should raise_error(TypeError)
  end

  it "raises an ArgumentError if not passed one argument" do
    -> { File.extname }.should raise_error(ArgumentError)
    -> { File.extname("foo.bar", "foo.baz") }.should raise_error(ArgumentError)
  end


  it "returns the extension for a multibyte filename" do
    File.extname('Имя.m4a').should == ".m4a"
  end

end
