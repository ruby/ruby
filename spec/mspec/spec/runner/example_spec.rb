require 'spec_helper'
require 'mspec/matchers/base'
require 'mspec/runner/mspec'
require 'mspec/mocks/mock'
require 'mspec/runner/example'

RSpec.describe ExampleState do
  it "is initialized with the ContextState, #it string, and #it block" do
    prc = lambda { }
    context = ContextState.new ""
    expect(ExampleState.new(context, "does", prc)).to be_kind_of(ExampleState)
  end
end

RSpec.describe ExampleState, "#describe" do
  before :each do
    @context = ContextState.new "Object#to_s"
    @state = ExampleState.new @context, "it"
  end

  it "returns the ContextState#description" do
    expect(@state.describe).to eq(@context.description)
  end
end

RSpec.describe ExampleState, "#it" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  it "returns the argument to the #it block" do
    expect(@state.it).to eq("it")
  end
end

RSpec.describe ExampleState, "#context=" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
    @context = ContextState.new "New#context"
  end

  it "sets the containing ContextState" do
    @state.context = @context
    expect(@state.context).to eq(@context)
  end

  it "resets the description" do
    expect(@state.description).to eq("describe it")
    @state.context = @context
    expect(@state.description).to eq("New#context it")
  end
end

RSpec.describe ExampleState, "#example" do
  before :each do
    @proc = lambda { }
    @state = ExampleState.new ContextState.new("describe"), "it", @proc
  end

  it "returns the #it block" do
    expect(@state.example).to eq(@proc)
  end
end

RSpec.describe ExampleState, "#filtered?" do
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
    expect(@state.filtered?).to eq(false)
  end

  it "returns false if MSpec include filters match this spec" do
    expect(@filter).to receive(:===).and_return(true)
    MSpec.register :include, @filter
    expect(@state.filtered?).to eq(false)
  end

  it "returns true if MSpec include filters do not match this spec" do
    expect(@filter).to receive(:===).and_return(false)
    MSpec.register :include, @filter
    expect(@state.filtered?).to eq(true)
  end

  it "returns false if MSpec exclude filters list is empty" do
    expect(@state.filtered?).to eq(false)
  end

  it "returns false if MSpec exclude filters do not match this spec" do
    expect(@filter).to receive(:===).and_return(false)
    MSpec.register :exclude, @filter
    expect(@state.filtered?).to eq(false)
  end

  it "returns true if MSpec exclude filters match this spec" do
    expect(@filter).to receive(:===).and_return(true)
    MSpec.register :exclude, @filter
    expect(@state.filtered?).to eq(true)
  end

  it "returns true if MSpec include and exclude filters match this spec" do
    expect(@filter).to receive(:===).twice.and_return(true)
    MSpec.register :include, @filter
    MSpec.register :exclude, @filter
    expect(@state.filtered?).to eq(true)
  end
end
