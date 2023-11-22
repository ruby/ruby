require_relative '../../spec_helper'

describe "Process.warmup" do
  ruby_version_is "3.3" do
    # The behavior is entirely implementation specific.
    # Other implementations are free to just make it a noop
    it "is implemented" do
      Process.warmup.should == true
    end
  end
end
