require 'spec_helper'
require 'mspec/matchers/base'
require 'mspec/runner/mspec'
require 'mspec/mocks/mock'
require 'mspec/runner/example'

describe ExampleState do
  it "is initialized with the ContextState, #it string, and #it block" do
    prc = lambda { }
    context = ContextState.new ""
    ExampleState.new(context, "does", prc).should be_kind_of(ExampleState)
  end
end

describe ExampleState, "#describe" do
  before :each do
    @context = ContextState.new "Object#to_s"
    @state = ExampleState.new @context, "it"
  end

  it "returns the ContextState#description" do
    @state.describe.should == @context.description
  end
end

describe ExampleState, "#it" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  it "returns the argument to the #it block" do
    @state.it.should == "it"
  end
end

describe ExampleState, "#context=" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
    @context = ContextState.new "New#context"
  end

  it "sets the containing ContextState" do
    @state.context = @context
    @state.context.should == @context
  end

  it "resets the description" do
    @state.description.should == "describe it"
    @state.context = @context
    @state.description.should == "New#context it"
  end
end

describe ExampleState, "#example" do
  before :each do
    @proc = lambda { }
    @state = ExampleState.new ContextState.new("describe"), "it", @proc
  end

  it "returns the #it block" do
    @state.example.should == @proc
  end
end

describe ExampleState, "#filtered?" do
  before :each do
    MSpec.store :include, []
    MSpec.store :exclude, []

    @state = ExampleState.new ContextState.new("describe"), "it"
    @filter = double("filter")
  end

  after :each do
    MSpec.store :include, []
    MSpec.store :exclude, []
  end

  it "returns false if MSpec include filters list is empty" do
    @state.filtered?.should == false
  end

  it "returns false if MSpec include filters match this spec" do
    @filter.should_receive(:===).and_return(true)
    MSpec.register :include, @filter
    @state.filtered?.should == false
  end

  it "returns true if MSpec include filters do not match this spec" do
    @filter.should_receive(:===).and_return(false)
    MSpec.register :include, @filter
    @state.filtered?.should == true
  end

  it "returns false if MSpec exclude filters list is empty" do
    @state.filtered?.should == false
  end

  it "returns false if MSpec exclude filters do not match this spec" do
    @filter.should_receive(:===).and_return(false)
    MSpec.register :exclude, @filter
    @state.filtered?.should == false
  end

  it "returns true if MSpec exclude filters match this spec" do
    @filter.should_receive(:===).and_return(true)
    MSpec.register :exclude, @filter
    @state.filtered?.should == true
  end

  it "returns true if MSpec include and exclude filters match this spec" do
    @filter.should_receive(:===).twice.and_return(true)
    MSpec.register :include, @filter
    MSpec.register :exclude, @filter
    @state.filtered?.should == true
  end
end
