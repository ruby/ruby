require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers/base'
require 'mspec/runner/mspec'
require 'mspec/mocks/mock'
require 'mspec/runner/context'
require 'mspec/runner/example'

RSpec.describe ContextState, "#describe" do
  before :each do
    @state = ContextState.new "C#m"
    @proc = proc { ScratchPad.record :a }
    ScratchPad.clear
  end

  it "evaluates the passed block" do
    @state.describe(&@proc)
    expect(ScratchPad.recorded).to eq(:a)
  end

  it "evaluates the passed block via #protect" do
    expect(@state).to receive(:protect).with("C#m", @proc, false)
    @state.describe(&@proc)
  end

  it "registers #parent as the current MSpec ContextState" do
    parent = ContextState.new ""
    @state.parent = parent
    expect(MSpec).to receive(:register_current).with(parent)
    @state.describe { }
  end

  it "registers self with MSpec when #shared? is true" do
    state = ContextState.new "something shared", :shared => true
    expect(MSpec).to receive(:register_shared).with(state)
    state.describe { }
  end
end

RSpec.describe ContextState, "#shared?" do
  it "returns false when the ContextState is not shared" do
    expect(ContextState.new("").shared?).to be_falsey
  end

  it "returns true when the ContextState is shared" do
    expect(ContextState.new("", {:shared => true}).shared?).to be_truthy
  end
end

RSpec.describe ContextState, "#to_s" do
  it "returns a description string for self when passed a Module" do
    expect(ContextState.new(Object).to_s).to eq("Object")
  end

  it "returns a description string for self when passed a String" do
    expect(ContextState.new("SomeClass").to_s).to eq("SomeClass")
  end
end

RSpec.describe ContextState, "#description" do
  before :each do
    @state = ContextState.new "when empty"
    @parent = ContextState.new "Toplevel"
  end

  it "returns a composite description string from self and all parents" do
    expect(@parent.description).to eq("Toplevel")
    expect(@state.description).to eq("when empty")
    @state.parent = @parent
    expect(@state.description).to eq("Toplevel when empty")
  end
end

RSpec.describe ContextState, "#it" do
  before :each do
    @state = ContextState.new ""
    @proc = lambda {|*| }

    @ex = ExampleState.new("", "", &@proc)
  end

  it "creates an ExampleState instance for the block" do
    expect(ExampleState).to receive(:new).with(@state, "it", @proc).and_return(@ex)
    @state.describe(&@proc)
    @state.it("it", &@proc)
  end

  it "calls registered :add actions" do
    expect(ExampleState).to receive(:new).with(@state, "it", @proc).and_return(@ex)

    add_action = double("add")
    expect(add_action).to receive(:add).with(@ex) { ScratchPad.record :add }
    MSpec.register :add, add_action

    @state.it("it", &@proc)
    expect(ScratchPad.recorded).to eq(:add)
    MSpec.unregister :add, add_action
  end
end

RSpec.describe ContextState, "#examples" do
  before :each do
    @state = ContextState.new ""
  end

  it "returns a list of all examples in this ContextState" do
    @state.it("first") { }
    @state.it("second") { }
    expect(@state.examples.size).to eq(2)
  end
end

RSpec.describe ContextState, "#before" do
  before :each do
    @state = ContextState.new ""
    @proc = lambda {|*| }
  end

  it "records the block for :each" do
    @state.before(:each, &@proc)
    expect(@state.before(:each)).to eq([@proc])
  end

  it "records the block for :all" do
    @state.before(:all, &@proc)
    expect(@state.before(:all)).to eq([@proc])
  end
end

RSpec.describe ContextState, "#after" do
  before :each do
    @state = ContextState.new ""
    @proc = lambda {|*| }
  end

  it "records the block for :each" do
    @state.after(:each, &@proc)
    expect(@state.after(:each)).to eq([@proc])
  end

  it "records the block for :all" do
    @state.after(:all, &@proc)
    expect(@state.after(:all)).to eq([@proc])
  end
end

RSpec.describe ContextState, "#pre" do
  before :each do
    @a = lambda {|*| }
    @b = lambda {|*| }
    @c = lambda {|*| }

    parent = ContextState.new ""
    parent.before(:each, &@c)
    parent.before(:all, &@c)

    @state = ContextState.new ""
    @state.parent = parent
  end

  it "returns before(:each) actions in the order they were defined" do
    @state.before(:each, &@a)
    @state.before(:each, &@b)
    expect(@state.pre(:each)).to eq([@c, @a, @b])
  end

  it "returns before(:all) actions in the order they were defined" do
    @state.before(:all, &@a)
    @state.before(:all, &@b)
    expect(@state.pre(:all)).to eq([@c, @a, @b])
  end
end

RSpec.describe ContextState, "#post" do
  before :each do
    @a = lambda {|*| }
    @b = lambda {|*| }
    @c = lambda {|*| }

    parent = ContextState.new ""
    parent.after(:each, &@c)
    parent.after(:all, &@c)

    @state = ContextState.new ""
    @state.parent = parent
  end

  it "returns after(:each) actions in the reverse order they were defined" do
    @state.after(:each, &@a)
    @state.after(:each, &@b)
    expect(@state.post(:each)).to eq([@b, @a, @c])
  end

  it "returns after(:all) actions in the reverse order they were defined" do
    @state.after(:all, &@a)
    @state.after(:all, &@b)
    expect(@state.post(:all)).to eq([@b, @a, @c])
  end
end

RSpec.describe ContextState, "#protect" do
  before :each do
    ScratchPad.record []
    @a = lambda {|*| ScratchPad << :a }
    @b = lambda {|*| ScratchPad << :b }
    @c = lambda {|*| raise Exception, "Fail!" }
  end

  it "returns true and does execute any blocks if check and MSpec.mode?(:pretend) are true" do
    expect(MSpec).to receive(:mode?).with(:pretend).and_return(true)
    expect(ContextState.new("").protect("message", [@a, @b])).to be_truthy
    expect(ScratchPad.recorded).to eq([])
  end

  it "executes the blocks if MSpec.mode?(:pretend) is false" do
    expect(MSpec).to receive(:mode?).with(:pretend).and_return(false)
    ContextState.new("").protect("message", [@a, @b])
    expect(ScratchPad.recorded).to eq([:a, :b])
  end

  it "executes the blocks if check is false" do
    ContextState.new("").protect("message", [@a, @b], false)
    expect(ScratchPad.recorded).to eq([:a, :b])
  end

  it "returns true if none of the blocks raise an exception" do
    expect(ContextState.new("").protect("message", [@a, @b])).to be_truthy
  end

  it "returns false if any of the blocks raise an exception" do
    expect(ContextState.new("").protect("message", [@a, @c, @b])).to be_falsey
  end
end

RSpec.describe ContextState, "#parent=" do
  before :each do
    @state = ContextState.new ""
    @parent = double("describe")
    allow(@parent).to receive(:parent).and_return(nil)
    allow(@parent).to receive(:child)
  end

  it "does not set self as a child of parent if shared" do
    expect(@parent).not_to receive(:child)
    state = ContextState.new "", :shared => true
    state.parent = @parent
  end

  it "does not set parents if shared" do
    state = ContextState.new "", :shared => true
    state.parent = @parent
    expect(state.parents).to eq([state])
  end

  it "sets self as a child of parent" do
    expect(@parent).to receive(:child).with(@state)
    @state.parent = @parent
  end

  it "creates the list of parents" do
    @state.parent = @parent
    expect(@state.parents).to eq([@parent, @state])
  end
end

RSpec.describe ContextState, "#parent" do
  before :each do
    @state = ContextState.new ""
    @parent = double("describe")
    allow(@parent).to receive(:parent).and_return(nil)
    allow(@parent).to receive(:child)
  end

  it "returns nil if parent has not been set" do
    expect(@state.parent).to be_nil
  end

  it "returns the parent" do
    @state.parent = @parent
    expect(@state.parent).to eq(@parent)
  end
end

RSpec.describe ContextState, "#parents" do
  before :each do
    @first = ContextState.new ""
    @second = ContextState.new ""
    @parent = double("describe")
    allow(@parent).to receive(:parent).and_return(nil)
    allow(@parent).to receive(:child)
  end

  it "returns a list of all enclosing ContextState instances" do
    @first.parent = @parent
    @second.parent = @first
    expect(@second.parents).to eq([@parent, @first, @second])
  end
end

RSpec.describe ContextState, "#child" do
  before :each do
    @first = ContextState.new ""
    @second = ContextState.new ""
    @parent = double("describe")
    allow(@parent).to receive(:parent).and_return(nil)
    allow(@parent).to receive(:child)
  end

  it "adds the ContextState to the list of contained ContextStates" do
    @first.child @second
    expect(@first.children).to eq([@second])
  end
end

RSpec.describe ContextState, "#children" do
  before :each do
    @parent = ContextState.new ""
    @first = ContextState.new ""
    @second = ContextState.new ""
  end

  it "returns the list of directly contained ContextStates" do
    @first.parent = @parent
    @second.parent = @first
    expect(@parent.children).to eq([@first])
    expect(@first.children).to eq([@second])
  end
end

RSpec.describe ContextState, "#state" do
  before :each do
    MSpec.store :before, []
    MSpec.store :after, []

    @state = ContextState.new ""
  end

  it "returns nil if no spec is being executed" do
    expect(@state.state).to eq(nil)
  end

  it "returns a ExampleState instance if an example is being executed" do
    ScratchPad.record @state
    @state.describe { }
    @state.it("") { ScratchPad.record ScratchPad.recorded.state }
    @state.process
    expect(@state.state).to eq(nil)
    expect(ScratchPad.recorded).to be_kind_of(ExampleState)
  end
end

RSpec.describe ContextState, "#process" do
  before :each do
    MSpec.store :before, []
    MSpec.store :after, []
    allow(MSpec).to receive(:register_current)

    @state = ContextState.new ""
    @state.describe { }

    @a = lambda {|*| ScratchPad << :a }
    @b = lambda {|*| ScratchPad << :b }
    ScratchPad.record []
  end

  it "calls each before(:all) block" do
    @state.before(:all, &@a)
    @state.before(:all, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([:a, :b])
  end

  it "calls each after(:all) block" do
    @state.after(:all, &@a)
    @state.after(:all, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([:b, :a])
  end

  it "calls each it block" do
    @state.it("one", &@a)
    @state.it("two", &@b)
    @state.process
    expect(ScratchPad.recorded).to eq([:a, :b])
  end

  it "does not call the #it block if #filtered? returns true" do
    @state.it("one", &@a)
    @state.it("two", &@b)
    allow(@state.examples.first).to receive(:filtered?).and_return(true)
    @state.process
    expect(ScratchPad.recorded).to eq([:b])
  end

  it "calls each before(:each) block" do
    @state.before(:each, &@a)
    @state.before(:each, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([:a, :b])
  end

  it "calls each after(:each) block" do
    @state.after(:each, &@a)
    @state.after(:each, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([:b, :a])
  end

  it "calls Mock.cleanup for each it block" do
    @state.it("") { }
    @state.it("") { }
    expect(Mock).to receive(:cleanup).twice
    @state.process
  end

  it "calls Mock.verify_count for each it block" do
    @state.it("") { }
    @state.it("") { }
    expect(Mock).to receive(:verify_count).twice
    @state.process
  end

  it "calls the describe block" do
    ScratchPad.record []
    @state.describe { ScratchPad << :a }
    @state.process
    expect(ScratchPad.recorded).to eq([:a])
  end

  it "creates a new ExampleState instance for each example" do
    ScratchPad.record @state
    @state.describe { }
    @state.it("it") { ScratchPad.record ScratchPad.recorded.state }
    @state.process
    expect(ScratchPad.recorded).to be_kind_of(ExampleState)
  end

  it "clears the expectations flag before evaluating the #it block" do
    MSpec.clear_expectations
    expect(MSpec).to receive(:clear_expectations)
    @state.it("it") { ScratchPad.record MSpec.expectation? }
    @state.process
    expect(ScratchPad.recorded).to be_falsey
  end

  it "shuffles the spec list if MSpec.randomize? is true" do
    MSpec.randomize = true
    begin
      expect(MSpec).to receive(:shuffle)
      @state.it("") { }
      @state.process
    ensure
      MSpec.randomize = false
    end
  end

  it "sets the current MSpec ContextState" do
    expect(MSpec).to receive(:register_current).with(@state)
    @state.process
  end

  it "resets the current MSpec ContextState to nil when there are examples" do
    expect(MSpec).to receive(:register_current).with(nil)
    @state.it("") { }
    @state.process
  end

  it "resets the current MSpec ContextState to nil when there are no examples" do
    expect(MSpec).to receive(:register_current).with(nil)
    @state.process
  end

  it "call #process on children when there are examples" do
    child = ContextState.new ""
    expect(child).to receive(:process)
    @state.child child
    @state.it("") { }
    @state.process
  end

  it "call #process on children when there are no examples" do
    child = ContextState.new ""
    expect(child).to receive(:process)
    @state.child child
    @state.process
  end
end

RSpec.describe ContextState, "#process" do
  before :each do
    MSpec.store :exception, []

    @state = ContextState.new ""
    @state.describe { }

    action = double("action")
    def action.exception(exc)
      ScratchPad.record :exception if exc.exception.is_a? SpecExpectationNotFoundError
    end
    MSpec.register :exception, action

    MSpec.clear_expectations
    ScratchPad.clear
  end

  after :each do
    MSpec.store :exception, nil
  end

  it "raises an SpecExpectationNotFoundError if an #it block does not contain an expectation" do
    @state.it("it") { }
    @state.process
    expect(ScratchPad.recorded).to eq(:exception)
  end

  it "does not raise an SpecExpectationNotFoundError if an #it block does contain an expectation" do
    @state.it("it") { MSpec.expectation }
    @state.process
    expect(ScratchPad.recorded).to be_nil
  end

  it "does not raise an SpecExpectationNotFoundError if the #it block causes a failure" do
    @state.it("it") { raise Exception, "Failed!" }
    @state.process
    expect(ScratchPad.recorded).to be_nil
  end
end

RSpec.describe ContextState, "#process" do
  before :each do
    MSpec.store :example, []

    @state = ContextState.new ""
    @state.describe { }

    example = double("example")
    def example.example(state, spec)
      ScratchPad << state << spec
    end
    MSpec.register :example, example

    ScratchPad.record []
  end

  after :each do
    MSpec.store :example, nil
  end

  it "calls registered :example actions with the current ExampleState and block" do
    @state.it("") { MSpec.expectation }
    @state.process

    expect(ScratchPad.recorded.first).to be_kind_of(ExampleState)
    expect(ScratchPad.recorded.last).to be_kind_of(Proc)
  end

  it "does not call registered example actions if the example has no block" do
    @state.it("empty example")
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end
end

RSpec.describe ContextState, "#process" do
  before :each do
    MSpec.store :before, []
    MSpec.store :after, []

    @state = ContextState.new ""
    @state.describe { }
    @state.it("") { MSpec.expectation }
  end

  after :each do
    MSpec.store :before, nil
    MSpec.store :after, nil
  end

  it "calls registered :before actions with the current ExampleState instance" do
    before = double("before")
    expect(before).to receive(:before) {
      ScratchPad.record :before
      @spec_state = @state.state
    }
    MSpec.register :before, before
    @state.process
    expect(ScratchPad.recorded).to eq(:before)
    expect(@spec_state).to be_kind_of(ExampleState)
  end

  it "calls registered :after actions with the current ExampleState instance" do
    after = double("after")
    expect(after).to receive(:after) {
      ScratchPad.record :after
      @spec_state = @state.state
    }
    MSpec.register :after, after
    @state.process
    expect(ScratchPad.recorded).to eq(:after)
    expect(@spec_state).to be_kind_of(ExampleState)
  end
end

RSpec.describe ContextState, "#process" do
  before :each do
    MSpec.store :enter, []
    MSpec.store :leave, []

    @state = ContextState.new "C#m"
    @state.describe { }
    @state.it("") { MSpec.expectation }
  end

  after :each do
    MSpec.store :enter, nil
    MSpec.store :leave, nil
  end

  it "calls registered :enter actions with the current #describe string" do
    enter = double("enter")
    expect(enter).to receive(:enter).with("C#m") { ScratchPad.record :enter }
    MSpec.register :enter, enter
    @state.process
    expect(ScratchPad.recorded).to eq(:enter)
  end

  it "calls registered :leave actions" do
    leave = double("leave")
    expect(leave).to receive(:leave) { ScratchPad.record :leave }
    MSpec.register :leave, leave
    @state.process
    expect(ScratchPad.recorded).to eq(:leave)
  end
end

RSpec.describe ContextState, "#process when an exception is raised in before(:all)" do
  before :each do
    MSpec.store :before, []
    MSpec.store :after, []

    @state = ContextState.new ""
    @state.describe { }

    @a = lambda {|*| ScratchPad << :a }
    @b = lambda {|*| ScratchPad << :b }
    ScratchPad.record []

    @state.before(:all) { raise Exception, "Fail!" }
  end

  after :each do
    MSpec.store :before, nil
    MSpec.store :after, nil
  end

  it "does not call before(:each)" do
    @state.before(:each, &@a)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call the it block" do
    @state.it("one", &@a)
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call after(:each)" do
    @state.after(:each, &@a)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call after(:each)" do
    @state.after(:all, &@a)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call Mock.verify_count" do
    @state.it("") { }
    expect(Mock).not_to receive(:verify_count)
    @state.process
  end

  it "calls Mock.cleanup" do
    @state.it("") { }
    expect(Mock).to receive(:cleanup)
    @state.process
  end
end

RSpec.describe ContextState, "#process when an exception is raised in before(:each)" do
  before :each do
    MSpec.store :before, []
    MSpec.store :after, []

    @state = ContextState.new ""
    @state.describe { }

    @a = lambda {|*| ScratchPad << :a }
    @b = lambda {|*| ScratchPad << :b }
    ScratchPad.record []

    @state.before(:each) { raise Exception, "Fail!" }
  end

  after :each do
    MSpec.store :before, nil
    MSpec.store :after, nil
  end

  it "does not call the it block" do
    @state.it("one", &@a)
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "calls after(:each)" do
    @state.after(:each, &@a)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([:a])
  end

  it "calls Mock.verify_count" do
    @state.it("") { }
    expect(Mock).to receive(:verify_count)
    @state.process
  end
end

RSpec.describe ContextState, "#process in pretend mode" do
  before :all do
    MSpec.register_mode :pretend
  end

  after :all do
    MSpec.clear_modes
  end

  before :each do
    ScratchPad.clear
    MSpec.store :before, []
    MSpec.store :after, []

    @state = ContextState.new ""
    @state.describe { }
    @state.it("") { }
  end

  after :each do
    MSpec.store :before, nil
    MSpec.store :after, nil
  end

  it "calls registered :before actions with the current ExampleState instance" do
    before = double("before")
    expect(before).to receive(:before) {
      ScratchPad.record :before
      @spec_state = @state.state
    }
    MSpec.register :before, before
    @state.process
    expect(ScratchPad.recorded).to eq(:before)
    expect(@spec_state).to be_kind_of(ExampleState)
  end

  it "calls registered :after actions with the current ExampleState instance" do
    after = double("after")
    expect(after).to receive(:after) {
      ScratchPad.record :after
      @spec_state = @state.state
    }
    MSpec.register :after, after
    @state.process
    expect(ScratchPad.recorded).to eq(:after)
    expect(@spec_state).to be_kind_of(ExampleState)
  end
end

RSpec.describe ContextState, "#process in pretend mode" do
  before :all do
    MSpec.register_mode :pretend
  end

  after :all do
    MSpec.clear_modes
  end

  before :each do
    MSpec.store :before, []
    MSpec.store :after, []

    @state = ContextState.new ""
    @state.describe { }

    @a = lambda {|*| ScratchPad << :a }
    @b = lambda {|*| ScratchPad << :b }
    ScratchPad.record []
  end

  it "calls the describe block" do
    ScratchPad.record []
    @state.describe { ScratchPad << :a }
    @state.process
    expect(ScratchPad.recorded).to eq([:a])
  end

  it "does not call any before(:all) block" do
    @state.before(:all, &@a)
    @state.before(:all, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call any after(:all) block" do
    @state.after(:all, &@a)
    @state.after(:all, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call any it block" do
    @state.it("one", &@a)
    @state.it("two", &@b)
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call any before(:each) block" do
    @state.before(:each, &@a)
    @state.before(:each, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call any after(:each) block" do
    @state.after(:each, &@a)
    @state.after(:each, &@b)
    @state.it("") { }
    @state.process
    expect(ScratchPad.recorded).to eq([])
  end

  it "does not call Mock.cleanup" do
    @state.it("") { }
    @state.it("") { }
    expect(Mock).not_to receive(:cleanup)
    @state.process
  end
end

RSpec.describe ContextState, "#process in pretend mode" do
  before :all do
    MSpec.register_mode :pretend
  end

  after :all do
    MSpec.clear_modes
  end

  before :each do
    MSpec.store :enter, []
    MSpec.store :leave, []

    @state = ContextState.new ""
    @state.describe { }
    @state.it("") { }
  end

  after :each do
    MSpec.store :enter, nil
    MSpec.store :leave, nil
  end

  it "calls registered :enter actions with the current #describe string" do
    enter = double("enter")
    expect(enter).to receive(:enter) { ScratchPad.record :enter }
    MSpec.register :enter, enter
    @state.process
    expect(ScratchPad.recorded).to eq(:enter)
  end

  it "calls registered :leave actions" do
    leave = double("leave")
    expect(leave).to receive(:leave) { ScratchPad.record :leave }
    MSpec.register :leave, leave
    @state.process
    expect(ScratchPad.recorded).to eq(:leave)
  end
end

RSpec.describe ContextState, "#it_should_behave_like" do
  before :each do
    @shared_desc = :shared_context
    @shared = ContextState.new(@shared_desc, :shared => true)
    allow(MSpec).to receive(:retrieve_shared).and_return(@shared)

    @state = ContextState.new "Top level"
    @a = lambda {|*| }
    @b = lambda {|*| }
  end

  it "raises an Exception if unable to find the shared ContextState" do
    expect(MSpec).to receive(:retrieve_shared).and_return(nil)
    expect { @state.it_should_behave_like "this" }.to raise_error(Exception)
  end

  describe "for nested ContextState instances" do
    before :each do
      @nested = ContextState.new "nested context"
      @nested.parents.unshift @shared

      @shared.children << @nested

      @nested_dup = @nested.dup
      allow(@nested).to receive(:dup).and_return(@nested_dup)
    end

    it "duplicates the nested ContextState" do
      @state.it_should_behave_like @shared_desc
      expect(@state.children.first).to equal(@nested_dup)
    end

    it "sets the parent of the nested ContextState to the containing ContextState" do
      @state.it_should_behave_like @shared_desc
      expect(@nested_dup.parent).to equal(@state)
    end

    it "sets the context for nested examples to the nested ContextState's dup" do
      @shared.it "an example", &@a
      @shared.it "another example", &@b
      @state.it_should_behave_like @shared_desc
      @nested_dup.examples.each { |x| expect(x.context).to equal(@nested_dup) }
    end

    it "omits the shored ContextState's description" do
      @nested.it "an example", &@a
      @nested.it "another example", &@b
      @state.it_should_behave_like @shared_desc

      expect(@nested_dup.description).to eq("Top level nested context")
      expect(@nested_dup.examples.first.description).to eq("Top level nested context an example")
      expect(@nested_dup.examples.last.description).to eq("Top level nested context another example")
    end
  end

  it "adds duped examples from the shared ContextState" do
    @shared.it "some method", &@a
    ex_dup = @shared.examples.first.dup
    allow(@shared.examples.first).to receive(:dup).and_return(ex_dup)

    @state.it_should_behave_like @shared_desc
    expect(@state.examples).to eq([ex_dup])
  end

  it "sets the context for examples to the containing ContextState" do
    @shared.it "an example", &@a
    @shared.it "another example", &@b
    @state.it_should_behave_like @shared_desc
    @state.examples.each { |x| expect(x.context).to equal(@state) }
  end

  it "adds before(:all) blocks from the shared ContextState" do
    @shared.before :all, &@a
    @shared.before :all, &@b
    @state.it_should_behave_like @shared_desc
    expect(@state.before(:all)).to include(*@shared.before(:all))
  end

  it "adds before(:each) blocks from the shared ContextState" do
    @shared.before :each, &@a
    @shared.before :each, &@b
    @state.it_should_behave_like @shared_desc
    expect(@state.before(:each)).to include(*@shared.before(:each))
  end

  it "adds after(:each) blocks from the shared ContextState" do
    @shared.after :each, &@a
    @shared.after :each, &@b
    @state.it_should_behave_like @shared_desc
    expect(@state.after(:each)).to include(*@shared.after(:each))
  end

  it "adds after(:all) blocks from the shared ContextState" do
    @shared.after :all, &@a
    @shared.after :all, &@b
    @state.it_should_behave_like @shared_desc
    expect(@state.after(:all)).to include(*@shared.after(:all))
  end
end

RSpec.describe ContextState, "#filter_examples" do
  before :each do
    @state = ContextState.new ""
    @state.it("one") { }
    @state.it("two") { }
  end

  it "removes examples that are filtered" do
    allow(@state.examples.first).to receive(:filtered?).and_return(true)
    expect(@state.examples.size).to eq(2)
    @state.filter_examples
    expect(@state.examples.size).to eq(1)
  end

  it "returns true if there are remaining examples to evaluate" do
    allow(@state.examples.first).to receive(:filtered?).and_return(true)
    expect(@state.filter_examples).to be_truthy
  end

  it "returns false if there are no remaining examples to evaluate" do
    allow(@state.examples.first).to receive(:filtered?).and_return(true)
    allow(@state.examples.last).to receive(:filtered?).and_return(true)
    expect(@state.filter_examples).to be_falsey
  end
end
