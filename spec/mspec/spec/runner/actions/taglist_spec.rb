require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/taglist'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/runner/tag'

describe TagListAction, "#include?" do
  it "returns true" do
    TagListAction.new.include?(:anything).should be_true
  end
end

describe TagListAction, "#===" do
  before :each do
    tag = SpecTag.new "fails:description"
    MSpec.stub(:read_tags).and_return([tag])
    @filter = double("MatchFilter").as_null_object
    MatchFilter.stub(:new).and_return(@filter)
    @action = TagListAction.new
    @action.load
  end

  it "returns true if filter === string returns true" do
    @filter.should_receive(:===).with("str").and_return(true)
    @action.===("str").should be_true
  end

  it "returns false if filter === string returns false" do
    @filter.should_receive(:===).with("str").and_return(false)
    @action.===("str").should be_false
  end
end

describe TagListAction, "#start" do
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
    $stdout.should == "\nListing specs tagged with 'fails', 'unstable'\n\n"
  end

  it "prints a banner for all tags" do
    action = TagListAction.new
    action.start
    $stdout.should == "\nListing all tagged specs\n\n"
  end
end

describe TagListAction, "#load" do
  before :each do
    @t1 = SpecTag.new "fails:I fail"
    @t2 = SpecTag.new "unstable:I'm unstable"
  end

  it "creates a MatchFilter for matching tags" do
    MSpec.should_receive(:read_tags).with(["fails"]).and_return([@t1])
    MatchFilter.should_receive(:new).with(nil, "I fail")
    TagListAction.new(["fails"]).load
  end

  it "creates a MatchFilter for all tags" do
    MSpec.should_receive(:read_tags).and_return([@t1, @t2])
    MatchFilter.should_receive(:new).with(nil, "I fail", "I'm unstable")
    TagListAction.new.load
  end

  it "does not create a MatchFilter if there are no matching tags" do
    MSpec.stub(:read_tags).and_return([])
    MatchFilter.should_not_receive(:new)
    TagListAction.new(["fails"]).load
  end
end

describe TagListAction, "#after" do
  before :each do
    @stdout = $stdout
    $stdout = IOStub.new

    @state = double("ExampleState")
    @state.stub(:description).and_return("str")

    @action = TagListAction.new
  end

  after :each do
    $stdout = @stdout
  end

  it "prints nothing if the filter does not match" do
    @action.should_receive(:===).with("str").and_return(false)
    @action.after(@state)
    $stdout.should == ""
  end

  it "prints the example description if the filter matches" do
    @action.should_receive(:===).with("str").and_return(true)
    @action.after(@state)
    $stdout.should == "str\n"
  end
end

describe TagListAction, "#register" do
  before :each do
    MSpec.stub(:register)
    @action = TagListAction.new
  end

  it "registers itself with MSpec for the :start event" do
    MSpec.should_receive(:register).with(:start, @action)
    @action.register
  end

  it "registers itself with MSpec for the :load event" do
    MSpec.should_receive(:register).with(:load, @action)
    @action.register
  end

  it "registers itself with MSpec for the :after event" do
    MSpec.should_receive(:register).with(:after, @action)
    @action.register
  end
end

describe TagListAction, "#unregister" do
  before :each do
    MSpec.stub(:unregister)
    @action = TagListAction.new
  end

  it "unregisters itself with MSpec for the :start event" do
    MSpec.should_receive(:unregister).with(:start, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :load event" do
    MSpec.should_receive(:unregister).with(:load, @action)
    @action.unregister
  end

  it "unregisters itself with MSpec for the :after event" do
    MSpec.should_receive(:unregister).with(:after, @action)
    @action.unregister
  end
end
