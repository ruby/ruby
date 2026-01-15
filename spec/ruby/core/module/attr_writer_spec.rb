require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/attr_added'

describe "Module#attr_writer" do
  it "creates a setter for each given attribute name" do
    c = Class.new do
      attr_writer :test1, "test2"
    end
    o = c.new

    o.respond_to?("test1").should == false
    o.respond_to?("test2").should == false

    o.respond_to?("test1=").should == true
    o.test1 = "test_1"
    o.instance_variable_get(:@test1).should == "test_1"

    o.respond_to?("test2=").should == true
    o.test2 = "test_2"
    o.instance_variable_get(:@test2).should == "test_2"
    o.send(:test1=,"test_1 updated")
    o.instance_variable_get(:@test1).should == "test_1 updated"
    o.send(:test2=,"test_2 updated")
    o.instance_variable_get(:@test2).should == "test_2 updated"
  end

  it "not allows for adding an attr_writer to an immediate" do
    class TrueClass
      attr_writer :spec_attr_writer
    end

    -> { true.spec_attr_writer = "a" }.should raise_error(FrozenError)
  end

  it "raises FrozenError if the receiver if frozen" do
    c = Class.new do
      attr_writer :foo
    end
    obj = c.new
    obj.freeze

    -> { obj.foo = 42 }.should raise_error(FrozenError)
  end

  it "converts non string/symbol names to strings using to_str" do
    (o = mock('test')).should_receive(:to_str).any_number_of_times.and_return("test")
    c = Class.new do
      attr_writer o
    end

    c.new.respond_to?("test").should == false
    c.new.respond_to?("test=").should == true
  end

  it "raises a TypeError when the given names can't be converted to strings using to_str" do
    o = mock('test1')
    -> { Class.new { attr_writer o } }.should raise_error(TypeError)
    (o = mock('123')).should_receive(:to_str).and_return(123)
    -> { Class.new { attr_writer o } }.should raise_error(TypeError)
  end

  it "applies current visibility to methods created" do
    c = Class.new do
      protected
      attr_writer :foo
    end

    -> { c.new.foo=1 }.should raise_error(NoMethodError)
  end

  it "is a public method" do
    Module.should have_public_instance_method(:attr_writer, false)
  end

  it "returns an array of defined method names as symbols" do
    Class.new do
      (attr_writer :foo, 'bar').should == [:foo=, :bar=]
    end
  end

  it_behaves_like :module_attr_added, :attr_writer
end
