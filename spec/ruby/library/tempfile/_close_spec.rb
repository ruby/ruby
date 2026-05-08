require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile#_close" do
  before :each do
    @tempfile = Tempfile.new("specs")
  end

  after :each do
    @tempfile.close!
  end

  it "is protected" do
    Tempfile.protected_instance_methods(false).should.include?(:_close)
  end

  it "closes self" do
    @tempfile.send(:_close)
    @tempfile.closed?.should == true
  end
end
