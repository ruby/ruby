# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

# TODO: Fix these
describe "File.basename" do
  it "returns the basename of a path (basic cases)" do
    File.basename("/Some/path/to/test.txt").should == "test.txt"
    File.basename(File.join("/tmp")).should == "tmp"
    File.basename(File.join(*%w( g f d s a b))).should == "b"
    File.basename("/tmp", ".*").should == "tmp"
    File.basename("/tmp", ".c").should == "tmp"
    File.basename("/tmp.c", ".c").should == "tmp"
    File.basename("/tmp.c", ".*").should == "tmp"
    File.basename("/tmp.c", ".?").should == "tmp.c"
    File.basename("/tmp.cpp", ".*").should == "tmp"
    File.basename("/tmp.cpp", ".???").should == "tmp.cpp"
    File.basename("/tmp.o", ".c").should == "tmp.o"
    File.basename(File.join("/tmp/")).should == "tmp"
    File.basename("/").should == "/"
    File.basename("//").should == "/"
    File.basename("dir///base", ".*").should == "base"
    File.basename("dir///base", ".c").should == "base"
    File.basename("dir///base.c", ".c").should == "base"
    File.basename("dir///base.c", ".*").should == "base"
    File.basename("dir///base.o", ".c").should == "base.o"
    File.basename("dir///base///").should == "base"
    File.basename("dir//base/", ".*").should == "base"
    File.basename("dir//base/", ".c").should == "base"
    File.basename("dir//base.c/", ".c").should == "base"
    File.basename("dir//base.c/", ".*").should == "base"
  end

  it "returns the last component of the filename" do
    File.basename('a').should == 'a'
    File.basename('/a').should == 'a'
    File.basename('/a/b').should == 'b'
    File.basename('/ab/ba/bag').should == 'bag'
    File.basename('/ab/ba/bag.txt').should == 'bag.txt'
    File.basename('/').should == '/'
    File.basename('/foo/bar/baz.rb', '.rb').should == 'baz'
    File.basename('baz.rb', 'z.rb').should == 'ba'
  end

  it "returns an string" do
    File.basename("foo").should be_kind_of(String)
  end

  it "returns the basename for unix format" do
    File.basename("/foo/bar").should == "bar"
    File.basename("/foo/bar.txt").should == "bar.txt"
    File.basename("bar.c").should == "bar.c"
    File.basename("/bar").should == "bar"
    File.basename("/bar/").should == "bar"

    # Considered UNC paths on Windows
    platform_is :windows do
      File.basename("baz//foo").should =="foo"
      File.basename("//foo/bar/baz").should == "baz"
    end
  end

  it "returns the basename for edge cases" do
    File.basename("").should == ""
    File.basename(".").should == "."
    File.basename("..").should == ".."
    platform_is_not :windows do
      File.basename("//foo/").should == "foo"
      File.basename("//foo//").should == "foo"
    end
    File.basename("foo/").should == "foo"
  end

  it "ignores a trailing directory separator" do
    File.basename("foo.rb/", '.rb').should == "foo"
    File.basename("bar.rb///", '.*').should == "bar"
  end

  it "returns the basename for unix suffix" do
    File.basename("bar.c", ".c").should == "bar"
    File.basename("bar.txt", ".txt").should == "bar"
    File.basename("/bar.txt", ".txt").should == "bar"
    File.basename("/foo/bar.txt", ".txt").should == "bar"
    File.basename("bar.txt", ".exe").should == "bar.txt"
    File.basename("bar.txt.exe", ".exe").should == "bar.txt"
    File.basename("bar.txt.exe", ".txt").should == "bar.txt.exe"
    File.basename("bar.txt", ".*").should == "bar"
    File.basename("bar.txt.exe", ".*").should == "bar.txt"
    File.basename("bar.txt.exe", ".txt.exe").should == "bar"
  end

  platform_is_not :windows do
    it "takes into consideration the platform path separator(s)" do
      File.basename("C:\\foo\\bar").should == "C:\\foo\\bar"
      File.basename("C:/foo/bar").should == "bar"
      File.basename("/foo/bar\\baz").should == "bar\\baz"
    end
  end

  platform_is :windows do
    it "takes into consideration the platform path separator(s)" do
      File.basename("C:\\foo\\bar").should == "bar"
      File.basename("C:/foo/bar").should == "bar"
      File.basename("/foo/bar\\baz").should == "baz"
    end
  end

  it "raises a TypeError if the arguments are not String types" do
    -> { File.basename(nil)          }.should raise_error(TypeError)
    -> { File.basename(1)            }.should raise_error(TypeError)
    -> { File.basename("bar.txt", 1) }.should raise_error(TypeError)
    -> { File.basename(true)         }.should raise_error(TypeError)
  end

  it "accepts an object that has a #to_path method" do
    File.basename(mock_to_path("foo.txt"))
  end

  it "raises an ArgumentError if passed more than two arguments" do
    -> { File.basename('bar.txt', '.txt', '.txt') }.should raise_error(ArgumentError)
  end

  # specific to MS Windows
  platform_is :windows do
    it "returns the basename for windows" do
      File.basename("C:\\foo\\bar\\baz.txt").should == "baz.txt"
      File.basename("C:\\foo\\bar").should == "bar"
      File.basename("C:\\foo\\bar\\").should == "bar"
      File.basename("C:\\foo").should == "foo"
      File.basename("C:\\").should == "\\"
    end

    it "returns basename windows unc" do
      File.basename("\\\\foo\\bar\\baz.txt").should == "baz.txt"
      File.basename("\\\\foo\\bar\\baz").should =="baz"
    end

    it "returns basename windows forward slash" do
      File.basename("C:/").should == "/"
      File.basename("C:/foo").should == "foo"
      File.basename("C:/foo/bar").should == "bar"
      File.basename("C:/foo/bar/").should == "bar"
      File.basename("C:/foo/bar//").should == "bar"
    end

    it "returns basename with windows suffix" do
      File.basename("c:\\bar.txt", ".txt").should == "bar"
      File.basename("c:\\foo\\bar.txt", ".txt").should == "bar"
      File.basename("c:\\bar.txt", ".exe").should == "bar.txt"
      File.basename("c:\\bar.txt.exe", ".exe").should == "bar.txt"
      File.basename("c:\\bar.txt.exe", ".txt").should == "bar.txt.exe"
      File.basename("c:\\bar.txt", ".*").should == "bar"
      File.basename("c:\\bar.txt.exe", ".*").should == "bar.txt"
    end
  end


  it "returns the extension for a multibyte filename" do
    File.basename('/path/Офис.m4a').should == "Офис.m4a"
  end

  it "returns the basename with the same encoding as the original" do
    basename = File.basename('C:/Users/Scuby Pagrubý'.encode(Encoding::Windows_1250))
    basename.should == 'Scuby Pagrubý'.encode(Encoding::Windows_1250)
    basename.encoding.should == Encoding::Windows_1250
  end

  it "returns a new unfrozen String" do
    exts = [nil, '.rb', '.*', '.txt']
    ['foo.rb','//', '/test/', 'test'].each do |example|
      exts.each do |ext|
        original = example.freeze
        result = if ext
                   File.basename(original, ext)
                 else
                   File.basename(original)
                 end
        result.should_not equal(original)
        result.frozen?.should == false
      end
    end
  end

end
