require_relative '../../spec_helper'

describe "Kernel#__dir__" do
  it "returns the real name of the directory containing the currently-executing file" do
    __dir__.should == File.realpath(File.dirname(__FILE__))
  end

  it "returns the expanded path of the directory when used in the main script" do
    fixtures_dir = File.dirname(fixture(__FILE__, '__dir__.rb'))
    Dir.chdir(fixtures_dir) do
      ruby_exe("__dir__.rb").should == "__dir__.rb\n#{fixtures_dir}\n"
    end
  end

  context "when used in eval with a given filename" do
    it "returns File.dirname(filename)" do
      eval("__dir__", nil, "foo.rb").should == "."
      eval("__dir__", nil, "foo/bar.rb").should == "foo"
    end
  end

  context "when used in eval with top level binding" do
    it "returns nil" do
      eval("__dir__", binding).should == nil
    end
  end
end
