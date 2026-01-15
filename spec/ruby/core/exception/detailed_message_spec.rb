require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Exception#detailed_message" do
  it "returns decorated message" do
    RuntimeError.new("new error").detailed_message.should == "new error (RuntimeError)"
  end

  it "is called by #full_message to allow message customization" do
    exception = Exception.new("new error")
    def exception.detailed_message(**)
      "<prefix>#{message}<suffix>"
    end
    exception.full_message(highlight: false).should.include? "<prefix>new error<suffix>"
  end

  it "returns just a message if exception class is anonymous" do
    Class.new(RuntimeError).new("message").detailed_message.should == "message"
  end

  it "returns 'unhandled exception' for an instance of RuntimeError with empty message" do
    RuntimeError.new("").detailed_message.should == "unhandled exception"
  end

  it "returns just class name for an instance other than RuntimeError with empty message" do
    DetailedMessageSpec::C.new("").detailed_message.should == "DetailedMessageSpec::C"
    StandardError.new("").detailed_message.should == "StandardError"
  end

  it "returns a generated class name for an instance of RuntimeError anonymous subclass with empty message" do
    klass = Class.new(RuntimeError)
    klass.new("").detailed_message.should =~ /\A#<Class:0x\h+>\z/
  end

  it "accepts highlight keyword argument and adds escape control sequences" do
    RuntimeError.new("new error").detailed_message(highlight: true).should == "\e[1mnew error (\e[1;4mRuntimeError\e[m\e[1m)\e[m"
  end

  it "accepts highlight keyword argument and adds escape control sequences for an instance of RuntimeError with empty message" do
    RuntimeError.new("").detailed_message(highlight: true).should == "\e[1;4munhandled exception\e[m"
  end

  it "accepts highlight keyword argument and adds escape control sequences for an instance other than RuntimeError with empty message" do
    StandardError.new("").detailed_message(highlight: true).should == "\e[1;4mStandardError\e[m"
  end

  it "allows and ignores other keyword arguments" do
    RuntimeError.new("new error").detailed_message(foo: true).should == "new error (RuntimeError)"
  end
end
