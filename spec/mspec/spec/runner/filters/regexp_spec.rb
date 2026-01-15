require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/regexp'

RSpec.describe MatchFilter, "#===" do
  before :each do
    @filter = RegexpFilter.new nil, 'a(b|c)', 'b[^ab]', 'cc?'
  end

  it "returns true if the argument matches any of the #initialize strings" do
    expect(@filter.===('ab')).to eq(true)
    expect(@filter.===('bc suffix')).to eq(true)
    expect(@filter.===('prefix cc')).to eq(true)
  end

  it "returns false if the argument matches none of the #initialize strings" do
    expect(@filter.===('aa')).to eq(false)
    expect(@filter.===('ba')).to eq(false)
    expect(@filter.===('prefix d suffix')).to eq(false)
  end
end

RSpec.describe RegexpFilter, "#to_regexp" do
  before :each do
    @filter = RegexpFilter.new nil
  end

  it "converts its arguments to Regexp instances" do
    expect(@filter.send(:to_regexp, 'a(b|c)', 'b[^ab]', 'cc?')).to eq([/a(b|c)/, /b[^ab]/, /cc?/])
  end
end
