require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Singleton#dup" do
  it "is prevented" do
    -> { SingletonSpecs::MyClass.instance.dup }.should raise_error(TypeError)
  end
end
