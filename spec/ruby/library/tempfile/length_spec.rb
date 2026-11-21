require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile#length" do
  it "is an alias of Tempfile#size" do
    Tempfile.instance_method(:length).should == Tempfile.instance_method(:size)
  end
end
