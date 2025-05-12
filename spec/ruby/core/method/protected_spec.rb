require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#protected?" do
  it "has been removed" do
    obj = MethodSpecs::Methods.new
    obj.method(:my_protected_method).should_not.respond_to?(:protected?)
  end
end
