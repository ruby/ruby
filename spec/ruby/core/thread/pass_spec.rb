require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread.pass" do
  it "returns nil" do
    Thread.pass.should == nil
  end
end
