require_relative '../../spec_helper'

describe "Proc#hash" do
  it "is provided" do
    proc {}.respond_to?(:hash).should == true
    -> {}.respond_to?(:hash).should == true
  end

  it "returns an Integer" do
    proc { 1 + 489 }.hash.should.is_a?(Integer)
  end

  it "is stable" do
    body = proc { :foo }
    proc(&body).hash.should == proc(&body).hash
  end
end
