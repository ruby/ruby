require_relative '../../spec_helper'
require 'coverage'

describe 'Coverage.running?' do
  it "returns false if coverage is not started" do
    Coverage.running?.should == false
  end

  it "returns true if coverage is started" do
    Coverage.start
    Coverage.running?.should == true
    Coverage.result
  end

  it "returns false if coverage was started and stopped" do
    Coverage.start
    Coverage.result
    Coverage.running?.should == false
  end
end