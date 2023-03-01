require_relative "../../spec_helper"
require_relative 'shared/inspect'
require 'set'

describe "Set#to_s" do
  it_behaves_like :set_inspect, :to_s

  it "is an alias of inspect" do
    set = Set.new
    set.method(:to_s).should == set.method(:inspect)
  end
end
