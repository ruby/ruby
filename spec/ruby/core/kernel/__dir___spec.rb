require_relative '../../spec_helper'

describe "Kernel#__dir__" do
  it "returns the real name of the directory containing the currently-executing file" do
    __dir__.should == File.realpath(File.dirname(__FILE__))
  end

  context "when used in eval with a given filename" do
    it "returns File.dirname(filename)" do
      eval("__dir__", nil, "foo.rb").should == "."
      eval("__dir__", nil, "foo/bar.rb").should == "foo"
    end
  end

  context "when used in eval with top level binding" do
    it "returns the real name of the directory containing the currently-executing file" do
      eval("__dir__", binding).should == File.realpath(File.dirname(__FILE__))
    end
  end
end
