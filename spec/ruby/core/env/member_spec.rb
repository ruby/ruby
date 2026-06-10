require_relative '../../spec_helper'

describe "ENV.member?" do
  it "is an alias of ENV.include?" do
    ENV.method(:member?).should == ENV.method(:include?)
  end
end
