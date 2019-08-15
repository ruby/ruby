require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/tagpurge'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/runner/tag'

describe TagPurgeAction, "#start" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new
  end

  after :each do
    $stdout = @stdout
  end

  it "prints a banner" do
    action = TagPurgeAction.new
    action.start
    $stdout.should == "\nRemoving tags not matching any specs\n\n"
  end
end

describe TagPurgeAction, "#load" do
  before :each do
    @t1 = SpecTag.new "fails:I fail"
    @t2 = SpecTag.new "unstable:I'm unstable"
  end

  it "creates a MatchFilter for all tags" do
    MSpec.should_receive(:read_tags).and_return([@t1, @t2])
    MatchFilter.should_receive(:new).with(nil, "I fail", "I'm unstable")
    TagPurgeAction.new.load
  end
end

describe TagPurgeAction, "#after" do
  before :each do
    @state = double("ExampleState")
    @state.stub(:description).and_return("str")

    @action = TagPurgeAction.new
  end

  it "does not save the description if the filter does not match" do
    @action.should_receive(:===).with("str").and_return(false)
    @action.after @state
    @action.matching.should == []
  end

  it "saves the description if the filter matches" do
    @action.should_receive(:===).with("str").and_return(true)
    @action.after @state
    @action.matching.should == ["str"]
  end
end

describe TagPurgeAction, "#unload" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new

    @t1 = SpecTag.new "fails:I fail"
    @t2 = SpecTag.new "unstable:I'm unstable"
    @t3 = SpecTag.new "fails:I'm unstable"

    MSpec.stub(:read_tags).and_return([@t1, @t2, @t3])
    MSpec.stub(:write_tags)

    @state = double("ExampleState")
    @state.stub(:description).and_return("I'm unstable")

    @action = TagPurgeAction.new
    @action.load
    @action.after @state
  end

  after :each do
    $stdout = @stdout
  end

  it "does not rewrite any tags if there were no tags for the specs" do
    MSpec.should_receive(:read_tags).and_return([])
    MSpec.should_receive(:delete_tags)
    MSpec.should_not_receive(:write_tags)

    @action.load
    @action.after @state
    @action.unload

    $stdout.should == ""
  end

  it "rewrites tags that were matched" do
    MSpec.should_receive(:write_tags).with([@t2, @t3])
    @action.unload
  end

  it "prints tags that were not matched" do
    @action.unload
    $stdout.should == "I fail\n"
  end
end

describe TagPurgeAction, "#unload" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new

    MSpec.stub(:read_tags).and_return([])

    @state = double("ExampleState")
    @state.stub(:description).and_return("I'm unstable")

    @action = TagPurgeAction.new
    @action.load
    @action.after @state
  end

  after :each do
    $stdout = @stdout
  end

  it "deletes the tag file if no tags were found" do
    MSpec.should_not_receive(:write_tags)
    MSpec.should_receive(:delete_tags)
    @action.unload
    $stdout.should == ""
  end
end

describe TagPurgeAction, "#register" do
  before :each do
    MSpec.stub(:register)
    @action = TagPurgeAction.new
  end

  it "registers itself with MSpec for the :unload event" do
    MSpec.should_receive(:register).with(:unload, @action)
    @action.register
  end
end

describe TagPurgeAction, "#unregister" do
  before :each do
    MSpec.stub(:unregister)
    @action = TagPurgeAction.new
  end

  it "unregisters itself with MSpec for the :unload event" do
    MSpec.should_receive(:unregister).with(:unload, @action)
    @action.unregister
  end
end
