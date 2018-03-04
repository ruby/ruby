require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Exception#message" do
  it "returns the class name if there is no message" do
    Exception.new.message.should == "Exception"
  end

  it "returns the message passed to #initialize" do
    Exception.new("Ouch!").message.should == "Ouch!"
  end

  it "calls #to_s on self" do
    exc = ExceptionSpecs::OverrideToS.new("you won't see this")
    exc.message.should == "this is from #to_s"
  end

  context "when #backtrace is redefined" do
    it "returns the Exception message" do
      e = Exception.new
      e.message.should == 'Exception'

      def e.backtrace; []; end
      e.message.should == 'Exception'
    end
  end
end
