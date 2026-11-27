require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile#unlink" do
  it "is an alias of Tempfile#delete" do
    Tempfile.instance_method(:unlink).should == Tempfile.instance_method(:delete)
  end
end
