require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Singleton.instance" do
  it "returns an instance of the singleton class" do
    SingletonSpecs::MyClass.instance.should.is_a?(SingletonSpecs::MyClass)
  end

  it "returns the same instance for multiple calls to instance" do
    SingletonSpecs::MyClass.instance.should.equal?(SingletonSpecs::MyClass.instance)
  end

  it "returns an instance of the singleton's subclasses" do
    SingletonSpecs::MyClassChild.instance.should.is_a?(SingletonSpecs::MyClassChild)
  end

  it "returns the same instance for multiple class to instance on subclasses" do
    SingletonSpecs::MyClassChild.instance.should.equal?(SingletonSpecs::MyClassChild.instance)
  end

  it "returns an instance of the singleton's clone" do
    klone = SingletonSpecs::MyClassChild.clone
    klone.instance.should.is_a?(klone)
  end

  it "returns the same instance for multiple class to instance on clones" do
    klone = SingletonSpecs::MyClassChild.clone
    klone.instance.should.equal?(klone.instance)
  end
end
