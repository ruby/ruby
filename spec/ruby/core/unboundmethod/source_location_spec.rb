require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#source_location" do
  before :each do
    @method = UnboundMethodSpecs::SourceLocation.method(:location).unbind
  end

  it "sets the first value to the path of the file in which the method was defined" do
    file = @method.source_location.first
    file.should be_an_instance_of(String)
    file.should == File.realpath('../fixtures/classes.rb', __FILE__)
  end

  it "sets the last value to an Integer representing the line on which the method was defined" do
    line = @method.source_location.last
    line.should be_an_instance_of(Integer)
    line.should == 5
  end

  it "returns the last place the method was defined" do
    UnboundMethodSpecs::SourceLocation.method(:redefined).unbind.source_location.last.should == 13
  end

  it "returns the location of the original method even if it was aliased" do
    UnboundMethodSpecs::SourceLocation.instance_method(:aka).source_location.last.should == 17
  end

  it "works for define_method methods" do
    line = nil
    cls = Class.new do
      line = __LINE__ + 1
      define_method(:foo) { }
    end

    method = cls.instance_method(:foo)
    method.source_location[0].should =~ /#{__FILE__}/
    method.source_location[1].should == line
  end

  it "works for define_singleton_method methods" do
    line = nil
    cls = Class.new do
      line = __LINE__ + 1
      define_singleton_method(:foo) { }
    end

    method = cls.method(:foo)
    method.source_location[0].should =~ /#{__FILE__}/
    method.source_location[1].should == line
  end
end
