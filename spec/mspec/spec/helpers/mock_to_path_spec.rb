require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#mock_to_path" do
  it "returns an object that responds to #to_path" do
    obj = mock_to_path("foo")
    obj.should be_a(MockObject)
    obj.should respond_to(:to_path)
    obj.to_path
  end

  it "returns the provided path when #to_path is called" do
    obj = mock_to_path("/tmp/foo")
    obj.to_path.should == "/tmp/foo"
  end
end
