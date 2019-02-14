require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# TODO: write spec for cloning classes and calling private methods
# TODO: write spec for private_methods not showing up via extended
describe "Singleton._load" do
  it "returns the singleton instance for anything passed in" do
    klass = SingletonSpecs::MyClass
    klass._load("").should be_equal(klass.instance)
    klass._load("42").should be_equal(klass.instance)
    klass._load(42).should be_equal(klass.instance)
  end

  it "returns the singleton instance for anything passed in to subclass" do
    subklass = SingletonSpecs::MyClassChild
    subklass._load("").should be_equal(subklass.instance)
    subklass._load("42").should be_equal(subklass.instance)
    subklass._load(42).should be_equal(subklass.instance)
  end
end
