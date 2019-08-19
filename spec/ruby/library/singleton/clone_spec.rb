require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Singleton#clone" do
  it "is prevented" do
    -> { SingletonSpecs::MyClass.instance.clone }.should raise_error(TypeError)
  end
end
