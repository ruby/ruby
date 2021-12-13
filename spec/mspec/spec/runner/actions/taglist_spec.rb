require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/taglist'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/runner/tag'

RSpec.describe TagListAction, "#include?" do
  it "returns true" do
    expect(TagListAction.new.include?(:anything)).to be_truthy
  end
end

RSpec.describe TagListAction, "#===" do
  before :each do
    tag = SpecTag.new "fails:description"
    allow(MSpec).to receive(:read_tags).and_return([tag])
    @filter = double("MatchFilter").as_null_object
    allow(MatchFilter).to receive(:new).and_return(@filter)
    @action = TagListAction.new
    @action.load
  end

  it "returns true if filter === string returns true" do
    expect(@filter).to receive(:===).with("str").and_return(true)
    expect(@action.===("str")).to be_truthy
  end

  it "returns false if filter === string returns false" do
    expect(@filter).to receive(:===).with("str").and_return(false)
    expect(@action.===("str")).to be_falsey
  end
end

RSpec.describe TagListAction, "#start" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new
  end

  after :each do
    $stdout = @stdout
  end

  it "prints a banner for specific tags" do
    action = TagListAction.new ["fails", "unstable"]
    action.start
    expect($stdout).to eq("\nListing specs tagged with 'fails', 'unstable'\n\n")
  end

  it "prints a banner for all tags" do
    action = TagListAction.new
    action.start
    expect($stdout).to eq("\nListing all tagged specs\n\n")
  end
end

RSpec.describe TagListAction, "#load" do
  before :each do
    @t1 = SpecTag.new "fails:I fail"
    @t2 = SpecTag.new "unstable:I'm unstable"
  end

  it "creates a MatchFilter for matching tags" do
    expect(MSpec).to receive(:read_tags).with(["fails"]).and_return([@t1])
    expect(MatchFilter).to receive(:new).with(nil, "I fail")
    TagListAction.new(["fails"]).load
  end

  it "creates a MatchFilter for all tags" do
    expect(MSpec).to receive(:read_tags).and_return([@t1, @t2])
    expect(MatchFilter).to receive(:new).with(nil, "I fail", "I'm unstable")
    TagListAction.new.load
  end

  it "does not create a MatchFilter if there are no matching tags" do
    allow(MSpec).to receive(:read_tags).and_return([])
    expect(MatchFilter).not_to receive(:new)
    TagListAction.new(["fails"]).load
  end
end

RSpec.describe TagListAction, "#after" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new

    @state = double("ExampleState")
    allow(@state).to receive(:description).and_return("str")

    @action = TagListAction.new
  end

  after :each do
    $stdout = @stdout
  end

  it "prints nothing if the filter does not match" do
    expect(@action).to receive(:===).with("str").and_return(false)
    @action.after(@state)
    expect($stdout).to eq("")
  end

  it "prints the example description if the filter matches" do
    expect(@action).to receive(:===).with("str").and_return(true)
    @action.after(@state)
    expect($stdout).to eq("str\n")
  end
end

RSpec.describe TagListAction, "#register" do
  before :each do
    allow(MSpec).to receive(:register)
    @action = TagListAction.new
  end

  it "registers itself with MSpec for the :start event" do
    expect(MSpec).to receive(:register).with(:start, @action)
    @action.register
  end

  it "registers itself with MSpec for the :load event" do
    expect(MSpec).to receive(:register).with(:load, @action)
    @action.register
  end

  it "registers itself with MSpec for the :after event" do
    expect(MSpec).to receive(:register).with(:after, @action)
    @action.register
  end
end

RSpec.describe TagListAction, "#unregister" do
  before :each do
    allow(MSpec).to receive(:unregister)
    @action = TagListAction.new
  end

  it "unregisters itself with MSpec for the :start event" do
    expect(MSpec).to receive(:unregister).with(:start, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :load event" do
    expect(MSpec).to receive(:unregister).with(:load, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :after event" do
    expect(MSpec).to receive(:unregister).with(:after, @action)
    @action.unregister
  end
end
