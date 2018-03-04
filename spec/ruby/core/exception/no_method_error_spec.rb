require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "NoMethodError.new" do
  it "allows passing method args" do
    NoMethodError.new("msg","name","args").args.should == "args"
  end

  it "does not require a name" do
    NoMethodError.new("msg").message.should == "msg"
  end
end

describe "NoMethodError#args" do
  it "returns an empty array if the caller method had no arguments" do
    begin
      NoMethodErrorSpecs::NoMethodErrorB.new.foo
    rescue Exception => e
      e.args.should == []
    end
  end

  it "returns an array with the same elements as passed to the method" do
    begin
      a = NoMethodErrorSpecs::NoMethodErrorA.new
      NoMethodErrorSpecs::NoMethodErrorB.new.foo(1,a)
    rescue Exception => e
      e.args.should == [1,a]
      e.args[1].should equal a
    end
  end
end

describe "NoMethodError#message" do
  it "for an undefined method match /undefined method/" do
    begin
      NoMethodErrorSpecs::NoMethodErrorD.new.foo
    rescue Exception => e
      e.should be_kind_of(NoMethodError)
    end
  end

  it "for an protected method match /protected method/" do
    begin
      NoMethodErrorSpecs::NoMethodErrorC.new.a_protected_method
    rescue Exception => e
      e.should be_kind_of(NoMethodError)
    end
  end

  it "for private method match /private method/" do
    begin
      NoMethodErrorSpecs::NoMethodErrorC.new.a_private_method
    rescue Exception => e
      e.should be_kind_of(NoMethodError)
      e.message.match(/private method/).should_not == nil
    end
  end

  it "calls receiver.inspect only when calling Exception#message" do
    ScratchPad.record []
    test_class = Class.new do
      def inspect
        ScratchPad << :inspect_called
        "<inspect>"
      end
    end
    instance = test_class.new
    begin
      instance.bar
    rescue Exception => e
      e.name.should == :bar
      ScratchPad.recorded.should == []
      e.message.should =~ /undefined method.+\bbar\b/
      ScratchPad.recorded.should == [:inspect_called]
    end
  end

  it "fallbacks to a simpler representation of the receiver when receiver.inspect raises an exception" do
    test_class = Class.new do
      def inspect
        raise NoMethodErrorSpecs::InstanceException
      end
    end
    instance = test_class.new
    begin
      instance.bar
    rescue Exception => e
      e.name.should == :bar
      message = e.message
      message.should =~ /undefined method.+\bbar\b/
      message.should include test_class.inspect
    end
  end
end
