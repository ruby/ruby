require_relative '../../spec_helper'

describe "Regexp#initialize" do
  it "is a private method" do
    Regexp.should have_private_method(:initialize)
  end

  it "raises a SecurityError on a Regexp literal" do
    -> { //.send(:initialize, "") }.should raise_error(SecurityError)
  end

  it "raises a TypeError on an initialized non-literal Regexp" do
    -> { Regexp.new("").send(:initialize, "") }.should raise_error(TypeError)
  end
end
