require 'spec_helper'
require 'mspec/guards'
require 'rbconfig'

describe SpecGuard, ".ruby_version" do
  before :each do
    stub_const "RUBY_VERSION", "8.2.3"
  end

  it "returns the full version for :full" do
    SpecGuard.ruby_version(:full).should == "8.2.3"
  end

  it "returns major.minor.tiny for :tiny" do
    SpecGuard.ruby_version(:tiny).should == "8.2.3"
  end

  it "returns major.minor.tiny for :teeny" do
    SpecGuard.ruby_version(:tiny).should == "8.2.3"
  end

  it "returns major.minor for :minor" do
    SpecGuard.ruby_version(:minor).should == "8.2"
  end

  it "defaults to :minor" do
    SpecGuard.ruby_version.should == "8.2"
  end

  it "returns major for :major" do
    SpecGuard.ruby_version(:major).should == "8"
  end
end

describe SpecGuard, "#yield?" do
  before :each do
    MSpec.clear_modes
    @guard = SpecGuard.new
    @guard.stub(:match?).and_return(false)
  end

  after :each do
    MSpec.unregister :add, @guard
    MSpec.clear_modes
    SpecGuard.clear_guards
  end

  it "returns true if MSpec.mode?(:unguarded) is true" do
    MSpec.register_mode :unguarded
    @guard.yield?.should == true
  end

  it "returns true if MSpec.mode?(:verify) is true" do
    MSpec.register_mode :verify
    @guard.yield?.should == true
  end

  it "returns true if MSpec.mode?(:verify) is true regardless of invert being true" do
    MSpec.register_mode :verify
    @guard.yield?(true).should == true
  end

  it "returns true if MSpec.mode?(:report) is true" do
    MSpec.register_mode :report
    @guard.yield?.should == true
  end

  it "returns true if MSpec.mode?(:report) is true regardless of invert being true" do
    MSpec.register_mode :report
    @guard.yield?(true).should == true
  end

  it "returns true if MSpec.mode?(:report_on) is true and SpecGuards.guards contains the named guard" do
    MSpec.register_mode :report_on
    SpecGuard.guards << :guard_name
    @guard.yield?.should == false
    @guard.name = :guard_name
    @guard.yield?.should == true
  end

  it "returns #match? if neither report nor verify mode are true" do
    @guard.stub(:match?).and_return(false)
    @guard.yield?.should == false
    @guard.stub(:match?).and_return(true)
    @guard.yield?.should == true
  end

  it "returns #match? if invert is true and neither report nor verify mode are true" do
    @guard.stub(:match?).and_return(false)
    @guard.yield?(true).should == true
    @guard.stub(:match?).and_return(true)
    @guard.yield?(true).should == false
  end
end

describe SpecGuard, "#match?" do
  before :each do
    @guard = SpecGuard.new
  end

  it "must be implemented in subclasses" do
    lambda {
      @guard.match?
    }.should raise_error("must be implemented by the subclass")
  end
end

describe SpecGuard, "#unregister" do
  before :each do
    MSpec.stub(:unregister)
    @guard = SpecGuard.new
  end

  it "unregisters from MSpec :add actions" do
    MSpec.should_receive(:unregister).with(:add, @guard)
    @guard.unregister
  end
end

describe SpecGuard, "#record" do
  after :each do
    SpecGuard.clear
  end

  it "saves the name of the guarded spec under the name of the guard" do
    guard = SpecGuard.new "a", "1.8"..."1.9"
    guard.name = :named_guard
    guard.record "SomeClass#action returns true"
    SpecGuard.report.should == {
      'named_guard a, 1.8...1.9' => ["SomeClass#action returns true"]
    }
  end
end

describe SpecGuard, ".guards" do
  it "returns an Array" do
    SpecGuard.guards.should be_kind_of(Array)
  end
end

describe SpecGuard, ".clear_guards" do
  it "resets the array to empty" do
    SpecGuard.guards << :guard
    SpecGuard.guards.should == [:guard]
    SpecGuard.clear_guards
    SpecGuard.guards.should == []
  end
end

describe SpecGuard, ".finish" do
  before :each do
    $stdout = @out = IOStub.new
  end

  after :each do
    $stdout = STDOUT
    SpecGuard.clear
  end

  it "prints the descriptions of the guarded specs" do
    guard = SpecGuard.new "a", "1.8"..."1.9"
    guard.name = :named_guard
    guard.record "SomeClass#action returns true"
    guard.record "SomeClass#reverse returns false"
    SpecGuard.finish
    $stdout.should == %[

2 specs omitted by guard: named_guard a, 1.8...1.9:

SomeClass#action returns true
SomeClass#reverse returns false

]
  end
end

describe SpecGuard, ".run_if" do
  before :each do
    @guard = SpecGuard.new
    ScratchPad.clear
  end

  it "yields if match? returns true" do
    @guard.stub(:match?).and_return(true)
    @guard.run_if(:name) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "does not yield if match? returns false" do
    @guard.stub(:match?).and_return(false)
    @guard.run_if(:name) { fail }
  end

  it "returns the result of the block if match? is true" do
    @guard.stub(:match?).and_return(true)
    @guard.run_if(:name) { 42 }.should == 42
  end

  it "returns nil if given a block and match? is false" do
    @guard.stub(:match?).and_return(false)
    @guard.run_if(:name) { 42 }.should == nil
  end

  it "returns what #match? returns when no block is given" do
    @guard.stub(:match?).and_return(true)
    @guard.run_if(:name).should == true
    @guard.stub(:match?).and_return(false)
    @guard.run_if(:name).should == false
  end
end

describe SpecGuard, ".run_unless" do
  before :each do
    @guard = SpecGuard.new
    ScratchPad.clear
  end

  it "yields if match? returns false" do
    @guard.stub(:match?).and_return(false)
    @guard.run_unless(:name) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "does not yield if match? returns true" do
    @guard.stub(:match?).and_return(true)
    @guard.run_unless(:name) { fail }
  end

  it "returns the result of the block if match? is false" do
    @guard.stub(:match?).and_return(false)
    @guard.run_unless(:name) { 42 }.should == 42
  end

  it "returns nil if given a block and match? is true" do
    @guard.stub(:match?).and_return(true)
    @guard.run_unless(:name) { 42 }.should == nil
  end

  it "returns the opposite of what #match? returns when no block is given" do
    @guard.stub(:match?).and_return(true)
    @guard.run_unless(:name).should == false
    @guard.stub(:match?).and_return(false)
    @guard.run_unless(:name).should == true
  end
end

describe Object, "#guard" do
  before :each do
    ScratchPad.clear
  end

  after :each do
    MSpec.clear_modes
  end

  it "allows to combine guards" do
    guard1 = VersionGuard.new '1.2.3', 'x.x.x'
    VersionGuard.stub(:new).and_return(guard1)
    guard2 = PlatformGuard.new :dummy
    PlatformGuard.stub(:new).and_return(guard2)

    guard1.stub(:match?).and_return(true)
    guard2.stub(:match?).and_return(true)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield
    end
    ScratchPad.recorded.should == :yield

    guard1.stub(:match?).and_return(false)
    guard2.stub(:match?).and_return(true)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end

    guard1.stub(:match?).and_return(true)
    guard2.stub(:match?).and_return(false)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end

    guard1.stub(:match?).and_return(false)
    guard2.stub(:match?).and_return(false)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end
  end

  it "yields when the Proc returns true" do
    guard -> { true } do
      ScratchPad.record :yield
    end
    ScratchPad.recorded.should == :yield
  end

  it "does not yield when the Proc returns false" do
    guard -> { false } do
      fail
    end
  end

  it "yields if MSpec.mode?(:unguarded) is true" do
    MSpec.register_mode :unguarded

    guard -> { false } do
      ScratchPad.record :yield1
    end
    ScratchPad.recorded.should == :yield1

    guard -> { true } do
      ScratchPad.record :yield2
    end
    ScratchPad.recorded.should == :yield2
  end

  it "yields if MSpec.mode?(:verify) is true" do
    MSpec.register_mode :verify

    guard -> { false } do
      ScratchPad.record :yield1
    end
    ScratchPad.recorded.should == :yield1

    guard -> { true } do
      ScratchPad.record :yield2
    end
    ScratchPad.recorded.should == :yield2
  end

  it "yields if MSpec.mode?(:report) is true" do
    MSpec.register_mode :report

    guard -> { false } do
      ScratchPad.record :yield1
    end
    ScratchPad.recorded.should == :yield1

    guard -> { true } do
      ScratchPad.record :yield2
    end
    ScratchPad.recorded.should == :yield2
  end

  it "raises an error if no Proc is given" do
    -> { guard :foo }.should raise_error(RuntimeError)
  end

  it "requires a block" do
    -> {
      guard(-> { true })
    }.should raise_error(LocalJumpError)
    -> {
      guard(-> { false })
    }.should raise_error(LocalJumpError)
  end
end

describe Object, "#guard_not" do
  before :each do
    ScratchPad.clear
  end

  it "allows to combine guards" do
    guard1 = VersionGuard.new '1.2.3', 'x.x.x'
    VersionGuard.stub(:new).and_return(guard1)
    guard2 = PlatformGuard.new :dummy
    PlatformGuard.stub(:new).and_return(guard2)

    guard1.stub(:match?).and_return(true)
    guard2.stub(:match?).and_return(true)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end

    guard1.stub(:match?).and_return(false)
    guard2.stub(:match?).and_return(true)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield1
    end
    ScratchPad.recorded.should == :yield1

    guard1.stub(:match?).and_return(true)
    guard2.stub(:match?).and_return(false)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield2
    end
    ScratchPad.recorded.should == :yield2

    guard1.stub(:match?).and_return(false)
    guard2.stub(:match?).and_return(false)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield3
    end
    ScratchPad.recorded.should == :yield3
  end

  it "yields when the Proc returns false" do
    guard_not -> { false } do
      ScratchPad.record :yield
    end
    ScratchPad.recorded.should == :yield
  end

  it "does not yield when the Proc returns true" do
    guard_not -> { true } do
      fail
    end
  end

  it "raises an error if no Proc is given" do
    -> { guard_not :foo }.should raise_error(RuntimeError)
  end

  it "requires a block" do
    -> {
      guard_not(-> { true })
    }.should raise_error(LocalJumpError)
    -> {
      guard_not(-> { false })
    }.should raise_error(LocalJumpError)
  end
end
