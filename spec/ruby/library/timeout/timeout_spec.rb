require_relative '../../spec_helper'
require 'timeout'

describe "Timeout.timeout" do
  it "raises Timeout::Error when it times out with no specified error type" do
    -> {
      Timeout.timeout(1) do
        sleep
      end
    }.should raise_error(Timeout::Error)
  end

  it "raises specified error type when it times out" do
    -> do
      Timeout.timeout(1, StandardError) do
        sleep
      end
    end.should raise_error(StandardError)
  end

  it "returns back the last value in the block" do
    Timeout.timeout(1) do
      42
    end.should == 42
  end
end
