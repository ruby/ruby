require_relative '../../spec_helper'

describe "ENV.to_s" do
  it "returns \"ENV\"" do
    ENV.to_s.should == "ENV"
  end
end
