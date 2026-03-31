require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#public?" do
  it "has been removed" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:my_public_method).unbind.should_not.respond_to?(:public?)
  end
end
