require_relative '../../spec_helper'
require 'time'

describe "Time.rfc822" do
  it "is an alias of Time.rfc2822" do
    Time.method(:rfc822).should == Time.method(:rfc2822)
  end
end
