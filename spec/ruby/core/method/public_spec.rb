require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#public?" do
  it "has been removed" do
    obj = MethodSpecs::Methods.new
    obj.method(:my_public_method).should_not.respond_to?(:public?)
  end
end
