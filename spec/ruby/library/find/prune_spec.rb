require_relative '../../spec_helper'
require 'find'

describe "Find.prune" do
  it "should throw :prune" do
    msg = catch(:prune) do
      Find.prune
    end

    msg.should == nil
  end
end
