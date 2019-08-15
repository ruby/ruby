require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/filter'
require 'mspec/runner/mspec'
require 'mspec/runner/tag'

describe ActionFilter do
  it "creates a filter when not passed a description" do
    MatchFilter.should_not_receive(:new)
    ActionFilter.new(nil, nil)
  end

  it "creates a filter from a single description" do
    MatchFilter.should_receive(:new).with(nil, "match me")
    ActionFilter.new(nil, "match me")
  end

  it "creates a filter from an array of descriptions" do
    MatchFilter.should_receive(:new).with(nil, "match me", "again")
    ActionFilter.new(nil, ["match me", "again"])
  end
end

describe ActionFilter, "#===" do
  before :each do
    MSpec.stub(:read_tags).and_return(["match"])
    @action = ActionFilter.new(nil, ["catch", "if you"])
  end

  it "returns false if there are no filters" do
    action = ActionFilter.new
    action.===("anything").should == false
  end

  it "returns true if the argument matches any of the descriptions" do
    @action.===("catch").should == true
    @action.===("if you can").should == true
  end

  it "returns false if the argument does not match any of the descriptions" do
    @action.===("patch me").should == false
    @action.===("if I can").should == false
  end
end

describe ActionFilter, "#load" do
  before :each do
    @tag = SpecTag.new "tag(comment):description"
  end

  it "creates a filter from a single tag" do
    MSpec.should_receive(:read_tags).with(["tag"]).and_return([@tag])
    MatchFilter.should_receive(:new).with(nil, "description")
    ActionFilter.new("tag", nil).load
  end

  it "creates a filter from an array of tags" do
    MSpec.should_receive(:read_tags).with(["tag", "key"]).and_return([@tag])
    MatchFilter.should_receive(:new).with(nil, "description")
    ActionFilter.new(["tag", "key"], nil).load
  end

  it "creates a filter from both tags and descriptions" do
    MSpec.should_receive(:read_tags).and_return([@tag])
    filter = ActionFilter.new("tag", ["match me", "again"])
    MatchFilter.should_receive(:new).with(nil, "description")
    filter.load
  end
end

describe ActionFilter, "#register" do
  it "registers itself with MSpec for the :load actions" do
    filter = ActionFilter.new
    MSpec.should_receive(:register).with(:load, filter)
    filter.register
  end
end

describe ActionFilter, "#unregister" do
  it "unregisters itself with MSpec for the :load actions" do
    filter = ActionFilter.new
    MSpec.should_receive(:unregister).with(:load, filter)
    filter.unregister
  end
end
