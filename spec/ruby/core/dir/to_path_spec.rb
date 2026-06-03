require_relative '../../spec_helper'

describe "Dir#to_path" do
  it "is an alias of Dir#path" do
    Dir.instance_method(:to_path).should == Dir.instance_method(:path)
  end
end
