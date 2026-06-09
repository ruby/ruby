require_relative '../../spec_helper'

describe "ENV.size" do
  it "returns the number of ENV entries" do
    orig = ENV.to_hash
    begin
      ENV.clear
      ENV["foo"] = "bar"
      ENV["baz"] = "boo"
      ENV.size.should == 2
    ensure
      ENV.replace orig
    end
  end
end
