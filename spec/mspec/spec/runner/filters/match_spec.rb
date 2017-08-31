require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/match'

describe MatchFilter, "#===" do
  before :each do
    @filter = MatchFilter.new nil, 'a', 'b', 'c'
  end

  it "returns true if the argument matches any of the #initialize strings" do
    @filter.===('aaa').should == true
    @filter.===('bccb').should == true
  end

  it "returns false if the argument matches none of the #initialize strings" do
    @filter.===('d').should == false
  end
end

describe MatchFilter, "#register" do
  it "registers itself with MSpec for the designated action list" do
    filter = MatchFilter.new :include
    MSpec.should_receive(:register).with(:include, filter)
    filter.register
  end
end

describe MatchFilter, "#unregister" do
  it "unregisters itself with MSpec for the designated action list" do
    filter = MatchFilter.new :exclude
    MSpec.should_receive(:unregister).with(:exclude, filter)
    filter.unregister
  end
end
