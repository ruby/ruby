require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/match'

RSpec.describe MatchFilter, "#===" do
  before :each do
    @filter = MatchFilter.new nil, 'a', 'b', 'c'
  end

  it "returns true if the argument matches any of the #initialize strings" do
    expect(@filter.===('aaa')).to eq(true)
    expect(@filter.===('bccb')).to eq(true)
  end

  it "returns false if the argument matches none of the #initialize strings" do
    expect(@filter.===('d')).to eq(false)
  end
end

RSpec.describe MatchFilter, "#register" do
  it "registers itself with MSpec for the designated action list" do
    filter = MatchFilter.new :include
    expect(MSpec).to receive(:register).with(:include, filter)
    filter.register
  end
end

RSpec.describe MatchFilter, "#unregister" do
  it "unregisters itself with MSpec for the designated action list" do
    filter = MatchFilter.new :exclude
    expect(MSpec).to receive(:unregister).with(:exclude, filter)
    filter.unregister
  end
end
