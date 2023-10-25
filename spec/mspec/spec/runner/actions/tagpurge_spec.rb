require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/tagpurge'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/runner/tag'

RSpec.describe TagPurgeAction, "#start" do
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
    expect($stdout).to eq("\nRemoving tags not matching any specs\n\n")
  end
end

RSpec.describe TagPurgeAction, "#load" do
  before :each do
    @t1 = SpecTag.new "fails:I fail"
    @t2 = SpecTag.new "unstable:I'm unstable"
  end

  it "creates a MatchFilter for all tags" do
    expect(MSpec).to receive(:read_tags).and_return([@t1, @t2])
    expect(MatchFilter).to receive(:new).with(nil, "I fail", "I'm unstable")
    TagPurgeAction.new.load
  end
end

RSpec.describe TagPurgeAction, "#after" do
  before :each do
    @state = double("ExampleState")
    allow(@state).to receive(:description).and_return("str")

    @action = TagPurgeAction.new
  end

  it "does not save the description if the filter does not match" do
    expect(@action).to receive(:===).with("str").and_return(false)
    @action.after @state
    expect(@action.matching).to eq([])
  end

  it "saves the description if the filter matches" do
    expect(@action).to receive(:===).with("str").and_return(true)
    @action.after @state
    expect(@action.matching).to eq(["str"])
  end
end

RSpec.describe TagPurgeAction, "#unload" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new

    @t1 = SpecTag.new "fails:I fail"
    @t2 = SpecTag.new "unstable:I'm unstable"
    @t3 = SpecTag.new "fails:I'm unstable"

    allow(MSpec).to receive(:read_tags).and_return([@t1, @t2, @t3])
    allow(MSpec).to receive(:write_tags)

    @state = double("ExampleState")
    allow(@state).to receive(:description).and_return("I'm unstable")

    @action = TagPurgeAction.new
    @action.load
    @action.after @state
  end

  after :each do
    $stdout = @stdout
  end

  it "does not rewrite any tags if there were no tags for the specs" do
    expect(MSpec).to receive(:read_tags).and_return([])
    expect(MSpec).to receive(:delete_tags)
    expect(MSpec).not_to receive(:write_tags)

    @action.load
    @action.after @state
    @action.unload

    expect($stdout).to eq("")
  end

  it "rewrites tags that were matched" do
    expect(MSpec).to receive(:write_tags).with([@t2, @t3])
    @action.unload
  end

  it "prints tags that were not matched" do
    @action.unload
    expect($stdout).to eq("I fail\n")
  end
end

RSpec.describe TagPurgeAction, "#unload" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new

    allow(MSpec).to receive(:read_tags).and_return([])

    @state = double("ExampleState")
    allow(@state).to receive(:description).and_return("I'm unstable")

    @action = TagPurgeAction.new
    @action.load
    @action.after @state
  end

  after :each do
    $stdout = @stdout
  end

  it "deletes the tag file if no tags were found" do
    expect(MSpec).not_to receive(:write_tags)
    expect(MSpec).to receive(:delete_tags)
    @action.unload
    expect($stdout).to eq("")
  end
end

RSpec.describe TagPurgeAction, "#register" do
  before :each do
    allow(MSpec).to receive(:register)
    @action = TagPurgeAction.new
  end

  it "registers itself with MSpec for the :unload event" do
    expect(MSpec).to receive(:register).with(:unload, @action)
    @action.register
  end
end

RSpec.describe TagPurgeAction, "#unregister" do
  before :each do
    allow(MSpec).to receive(:unregister)
    @action = TagPurgeAction.new
  end

  it "unregisters itself with MSpec for the :unload event" do
    expect(MSpec).to receive(:unregister).with(:unload, @action)
    @action.unregister
  end
end
