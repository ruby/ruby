require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/filter'
require 'mspec/runner/mspec'
require 'mspec/runner/tag'

RSpec.describe ActionFilter do
  it "creates a filter when not passed a description" do
    expect(MatchFilter).not_to receive(:new)
    ActionFilter.new(nil, nil)
  end

  it "creates a filter from a single description" do
    expect(MatchFilter).to receive(:new).with(nil, "match me")
    ActionFilter.new(nil, "match me")
  end

  it "creates a filter from an array of descriptions" do
    expect(MatchFilter).to receive(:new).with(nil, "match me", "again")
    ActionFilter.new(nil, ["match me", "again"])
  end
end

RSpec.describe ActionFilter, "#===" do
  before :each do
    allow(MSpec).to receive(:read_tags).and_return(["match"])
    @action = ActionFilter.new(nil, ["catch", "if you"])
  end

  it "returns false if there are no filters" do
    action = ActionFilter.new
    expect(action.===("anything")).to eq(false)
  end

  it "returns true if the argument matches any of the descriptions" do
    expect(@action.===("catch")).to eq(true)
    expect(@action.===("if you can")).to eq(true)
  end

  it "returns false if the argument does not match any of the descriptions" do
    expect(@action.===("patch me")).to eq(false)
    expect(@action.===("if I can")).to eq(false)
  end
end

RSpec.describe ActionFilter, "#load" do
  before :each do
    @tag = SpecTag.new "tag(comment):description"
  end

  it "creates a filter from a single tag" do
    expect(MSpec).to receive(:read_tags).with(["tag"]).and_return([@tag])
    expect(MatchFilter).to receive(:new).with(nil, "description")
    ActionFilter.new("tag", nil).load
  end

  it "creates a filter from an array of tags" do
    expect(MSpec).to receive(:read_tags).with(["tag", "key"]).and_return([@tag])
    expect(MatchFilter).to receive(:new).with(nil, "description")
    ActionFilter.new(["tag", "key"], nil).load
  end

  it "creates a filter from both tags and descriptions" do
    expect(MSpec).to receive(:read_tags).and_return([@tag])
    filter = ActionFilter.new("tag", ["match me", "again"])
    expect(MatchFilter).to receive(:new).with(nil, "description")
    filter.load
  end
end

RSpec.describe ActionFilter, "#register" do
  it "registers itself with MSpec for the :load actions" do
    filter = ActionFilter.new
    expect(MSpec).to receive(:register).with(:load, filter)
    filter.register
  end
end

RSpec.describe ActionFilter, "#unregister" do
  it "unregisters itself with MSpec for the :load actions" do
    filter = ActionFilter.new
    expect(MSpec).to receive(:unregister).with(:load, filter)
    filter.unregister
  end
end
