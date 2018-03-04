require_relative '../spec_helper'
require_relative '../fixtures/code_loading'
require_relative 'shared/__FILE__'

describe "The __FILE__ pseudo-variable" do
  it "raises a SyntaxError if assigned to" do
    lambda { eval("__FILE__ = 1") }.should raise_error(SyntaxError)
  end

  it "equals (eval) inside an eval" do
    eval("__FILE__").should == "(eval)"
  end
end

describe "The __FILE__ pseudo-variable" do
  it_behaves_like :language___FILE__, :require, CodeLoadingSpecs::Method.new
end

describe "The __FILE__ pseudo-variable" do
  it_behaves_like :language___FILE__, :require, Kernel
end

describe "The __FILE__ pseudo-variable" do
  it_behaves_like :language___FILE__, :load, CodeLoadingSpecs::Method.new
end

describe "The __FILE__ pseudo-variable" do
  it_behaves_like :language___FILE__, :load, Kernel
end
