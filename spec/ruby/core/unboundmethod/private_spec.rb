require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#private?" do
  it "has been removed" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:my_private_method).unbind.should_not.respond_to?(:private?)
  end
end
