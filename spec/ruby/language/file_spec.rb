require_relative '../spec_helper'
require_relative '../fixtures/code_loading'
require_relative 'shared/__FILE__'

describe "The __FILE__ pseudo-variable" do
  it "raises a SyntaxError if assigned to" do
    -> { eval("__FILE__ = 1") }.should raise_error(SyntaxError)
  end

  ruby_version_is ""..."3.3" do
    it "equals (eval) inside an eval" do
      eval("__FILE__").should == "(eval)"
    end
  end

  ruby_version_is "3.3" do
    it "equals (eval at __FILE__:__LINE__) inside an eval" do
      eval("__FILE__").should == "(eval at #{__FILE__}:#{__LINE__})"
    end
  end
end

describe "The __FILE__ pseudo-variable with require" do
  it_behaves_like :language___FILE__, :require, Kernel
end

describe "The __FILE__ pseudo-variable with load" do
  it_behaves_like :language___FILE__, :load, Kernel
end
