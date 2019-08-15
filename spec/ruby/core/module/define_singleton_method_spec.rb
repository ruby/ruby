require_relative '../../spec_helper'

describe "Module#define_singleton_method" do
  it "defines the given method as an class method with the given name in self" do
    klass = Module.new do
      define_singleton_method :a do
        42
      end
      define_singleton_method(:b, -> x { 2*x })
    end

    klass.a.should == 42
    klass.b(10).should == 20
  end
end
