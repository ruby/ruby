require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Singleton.allocate" do
  it "is a private method" do
    -> { SingletonSpecs::MyClass.allocate }.should raise_error(NoMethodError)
  end
end
