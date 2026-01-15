require_relative '../../spec_helper'
require_relative 'shared/path'

describe "File#path" do
  it_behaves_like :file_path, :path
end

describe "File.path" do
  before :each do
    @name = tmp("file_path")
  end

  after :each do
    rm_r @name
  end

  it "returns the string argument without any change" do
    File.path("abc").should == "abc"
    File.path("./abc").should == "./abc"
    File.path("../abc").should == "../abc"
    File.path("/./a/../bc").should == "/./a/../bc"
  end

  it "returns path for File argument" do
    File.open(@name, "w") do |f|
      File.path(f).should == @name
    end
  end

  it "returns path for Pathname argument" do
    require "pathname"
    File.path(Pathname.new(@name)).should == @name
  end

  it "calls #to_path for non-string argument and returns result" do
    path = mock("path")
    path.should_receive(:to_path).and_return("abc")
    File.path(path).should == "abc"
  end

  it "raises TypeError when #to_path result is not a string" do
    path = mock("path")
    path.should_receive(:to_path).and_return(nil)
    -> { File.path(path) }.should raise_error TypeError

    path = mock("path")
    path.should_receive(:to_path).and_return(42)
    -> { File.path(path) }.should raise_error TypeError
  end

  it "raises ArgumentError for string argument contains NUL character" do
    -> { File.path("\0") }.should raise_error ArgumentError
    -> { File.path("a\0") }.should raise_error ArgumentError
    -> { File.path("a\0c") }.should raise_error ArgumentError
  end

  it "raises ArgumentError when #to_path result contains NUL character" do
    path = mock("path")
    path.should_receive(:to_path).and_return("\0")
    -> { File.path(path) }.should raise_error ArgumentError

    path = mock("path")
    path.should_receive(:to_path).and_return("a\0")
    -> { File.path(path) }.should raise_error ArgumentError

    path = mock("path")
    path.should_receive(:to_path).and_return("a\0c")
    -> { File.path(path) }.should raise_error ArgumentError
  end

  it "raises Encoding::CompatibilityError for ASCII-incompatible string argument" do
    path = "abc".encode(Encoding::UTF_32BE)
    -> { File.path(path) }.should raise_error Encoding::CompatibilityError
  end

  it "raises Encoding::CompatibilityError when #to_path result is ASCII-incompatible" do
    path = mock("path")
    path.should_receive(:to_path).and_return("abc".encode(Encoding::UTF_32BE))
    -> { File.path(path) }.should raise_error Encoding::CompatibilityError
  end
end
