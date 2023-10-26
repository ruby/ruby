require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#attr_reader" do
  it "creates a getter for each given attribute name" do
    c = Class.new do
      attr_reader :a, "b"

      def initialize
        @a = "test"
        @b = "test2"
      end
    end

    o = c.new
    %w{a b}.each do |x|
      o.respond_to?(x).should == true
      o.respond_to?("#{x}=").should == false
    end

    o.a.should == "test"
    o.b.should == "test2"
    o.send(:a).should == "test"
    o.send(:b).should == "test2"
  end

  it "not allows for adding an attr_reader to an immediate" do
    class TrueClass
      attr_reader :spec_attr_reader
    end

    -> { true.instance_variable_set("@spec_attr_reader", "a") }.should raise_error(RuntimeError)
  end

  it "converts non string/symbol names to strings using to_str" do
    (o = mock('test')).should_receive(:to_str).any_number_of_times.and_return("test")
    c = Class.new do
      attr_reader o
    end

    c.new.respond_to?("test").should == true
    c.new.respond_to?("test=").should == false
  end

  it "raises a TypeError when the given names can't be converted to strings using to_str" do
    o = mock('o')
    -> { Class.new { attr_reader o } }.should raise_error(TypeError)
    (o = mock('123')).should_receive(:to_str).and_return(123)
    -> { Class.new { attr_reader o } }.should raise_error(TypeError)
  end

  it "applies current visibility to methods created" do
    c = Class.new do
      protected
      attr_reader :foo
    end

    -> { c.new.foo }.should raise_error(NoMethodError)
  end

  it "is a public method" do
    Module.should have_public_instance_method(:attr_reader, false)
  end

  it "returns an array of defined method names as symbols" do
    Class.new do
      (attr_reader :foo, 'bar').should == [:foo, :bar]
    end
  end
end
