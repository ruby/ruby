require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#protected?" do
  it "has been removed" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:my_protected_method).unbind.should_not.respond_to?(:protected?)
  end
end
