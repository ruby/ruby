require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#private?" do
  it "has been removed" do
    obj = MethodSpecs::Methods.new
    obj.method(:my_private_method).should_not.respond_to?(:private?)
  end
end
