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
end
