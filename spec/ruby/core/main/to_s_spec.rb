require_relative '../../spec_helper'

describe "main#to_s" do
  it "returns 'main'" do
    eval('to_s', TOPLEVEL_BINDING).should == "main"
  end
end
