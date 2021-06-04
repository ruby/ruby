require_relative '../../spec_helper'

describe "KeyError" do
  ruby_version_is "2.6" do
    it "accepts :receiver and :key options" do
      receiver = mock("receiver")
      key = mock("key")

      error = KeyError.new(receiver: receiver, key: key)

      error.receiver.should == receiver
      error.key.should == key

      error = KeyError.new("message", receiver: receiver, key: key)

      error.message.should == "message"
      error.receiver.should == receiver
      error.key.should == key
    end
  end
end
