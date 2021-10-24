require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Exception#to_s" do
  it "returns the self's name if no message is set" do
    Exception.new.to_s.should == 'Exception'
    ExceptionSpecs::Exceptional.new.to_s.should == 'ExceptionSpecs::Exceptional'
  end

  it "returns self's message if set" do
    ExceptionSpecs::Exceptional.new('!!').to_s.should == '!!'
  end

  it "calls #to_s on the message" do
    message = mock("message")
    message.should_receive(:to_s).and_return("message")
    ExceptionSpecs::Exceptional.new(message).to_s.should == "message"
  end
end

describe "NameError#to_s" do
  it "raises its own message for an undefined variable" do
    begin
      puts not_defined
    rescue => exception
      exception.message.should =~ /undefined local variable or method `not_defined'/
    end
  end

  it "raises its own message for an undefined constant" do
    begin
      puts NotDefined
    rescue => exception
      exception.message.should =~ /uninitialized constant NotDefined/
    end
  end
end
