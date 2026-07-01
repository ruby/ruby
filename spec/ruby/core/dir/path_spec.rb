require_relative '../../spec_helper'

describe "Dir#path" do
  it "is an alias of Dir#to_path" do
    Dir.instance_method(:path).should == Dir.instance_method(:to_path)
  end
end
