require_relative '../../spec_helper'

describe "Dir.getwd" do
  it "is an alias of Dir.pwd" do
    Dir.method(:getwd).should == Dir.method(:pwd)
  end
end
