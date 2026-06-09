require_relative '../../spec_helper'

describe "Regexp.escape" do
  it "is an alias of Regexp.quote" do
    Regexp.method(:escape).should == Regexp.method(:quote)
  end
end
