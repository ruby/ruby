require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'
require 'mspec/mocks'

RSpec.describe Object, "#mock_to_path" do
  before :each do
    state = double("run state").as_null_object
    expect(MSpec).to receive(:current).and_return(state)
  end

  it "returns an object that responds to #to_path" do
    obj = mock_to_path("foo")
    expect(obj).to be_a(MockObject)
    expect(obj).to respond_to(:to_path)
    obj.to_path
  end

  it "returns the provided path when #to_path is called" do
    obj = mock_to_path("/tmp/foo")
    expect(obj.to_path).to eq("/tmp/foo")
  end
end
