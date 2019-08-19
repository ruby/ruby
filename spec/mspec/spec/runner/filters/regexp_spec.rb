require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/regexp'

describe MatchFilter, "#===" do
  before :each do
    @filter = RegexpFilter.new nil, 'a(b|c)', 'b[^ab]', 'cc?'
  end

  it "returns true if the argument matches any of the #initialize strings" do
    @filter.===('ab').should == true
    @filter.===('bc suffix').should == true
    @filter.===('prefix cc').should == true
  end

  it "returns false if the argument matches none of the #initialize strings" do
    @filter.===('aa').should == false
    @filter.===('ba').should == false
    @filter.===('prefix d suffix').should == false
  end
end

describe RegexpFilter, "#to_regexp" do
  before :each do
    @filter = RegexpFilter.new nil
  end

  it "converts its arguments to Regexp instances" do
    @filter.send(:to_regexp, 'a(b|c)', 'b[^ab]', 'cc?').should == [/a(b|c)/, /b[^ab]/, /cc?/]
  end
end
