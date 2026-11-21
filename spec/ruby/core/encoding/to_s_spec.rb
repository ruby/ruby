require_relative "../../spec_helper"

describe "Encoding#to_s" do
  it "is an alias of Encoding#name" do
    Encoding.instance_method(:to_s).should == Encoding.instance_method(:name)
  end
end
