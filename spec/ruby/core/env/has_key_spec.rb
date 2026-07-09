require_relative '../../spec_helper'

describe "ENV.has_key?" do
  it "is an alias of ENV.include?" do
    ENV.method(:has_key?).should == ENV.method(:include?)
  end
end
