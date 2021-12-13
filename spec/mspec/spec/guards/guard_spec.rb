require 'spec_helper'
require 'mspec/guards'
require 'rbconfig'

RSpec.describe SpecGuard, ".ruby_version" do
  before :each do
    stub_const "RUBY_VERSION", "8.2.3"
  end

  it "returns the full version for :full" do
    expect(SpecGuard.ruby_version(:full)).to eq("8.2.3")
  end

  it "returns major.minor.tiny for :tiny" do
    expect(SpecGuard.ruby_version(:tiny)).to eq("8.2.3")
  end

  it "returns major.minor.tiny for :teeny" do
    expect(SpecGuard.ruby_version(:tiny)).to eq("8.2.3")
  end

  it "returns major.minor for :minor" do
    expect(SpecGuard.ruby_version(:minor)).to eq("8.2")
  end

  it "defaults to :minor" do
    expect(SpecGuard.ruby_version).to eq("8.2")
  end

  it "returns major for :major" do
    expect(SpecGuard.ruby_version(:major)).to eq("8")
  end
end

RSpec.describe SpecGuard, "#yield?" do
  before :each do
    MSpec.clear_modes
    @guard = SpecGuard.new
    allow(@guard).to receive(:match?).and_return(false)
  end

  after :each do
    MSpec.unregister :add, @guard
    MSpec.clear_modes
    SpecGuard.clear_guards
  end

  it "returns true if MSpec.mode?(:unguarded) is true" do
    MSpec.register_mode :unguarded
    expect(@guard.yield?).to eq(true)
  end

  it "returns true if MSpec.mode?(:verify) is true" do
    MSpec.register_mode :verify
    expect(@guard.yield?).to eq(true)
  end

  it "returns true if MSpec.mode?(:verify) is true regardless of invert being true" do
    MSpec.register_mode :verify
    expect(@guard.yield?(true)).to eq(true)
  end

  it "returns true if MSpec.mode?(:report) is true" do
    MSpec.register_mode :report
    expect(@guard.yield?).to eq(true)
  end

  it "returns true if MSpec.mode?(:report) is true regardless of invert being true" do
    MSpec.register_mode :report
    expect(@guard.yield?(true)).to eq(true)
  end

  it "returns true if MSpec.mode?(:report_on) is true and SpecGuards.guards contains the named guard" do
    MSpec.register_mode :report_on
    SpecGuard.guards << :guard_name
    expect(@guard.yield?).to eq(false)
    @guard.name = :guard_name
    expect(@guard.yield?).to eq(true)
  end

  it "returns #match? if neither report nor verify mode are true" do
    allow(@guard).to receive(:match?).and_return(false)
    expect(@guard.yield?).to eq(false)
    allow(@guard).to receive(:match?).and_return(true)
    expect(@guard.yield?).to eq(true)
  end

  it "returns #match? if invert is true and neither report nor verify mode are true" do
    allow(@guard).to receive(:match?).and_return(false)
    expect(@guard.yield?(true)).to eq(true)
    allow(@guard).to receive(:match?).and_return(true)
    expect(@guard.yield?(true)).to eq(false)
  end
end

RSpec.describe SpecGuard, "#match?" do
  before :each do
    @guard = SpecGuard.new
  end

  it "must be implemented in subclasses" do
    expect {
      @guard.match?
    }.to raise_error("must be implemented by the subclass")
  end
end

RSpec.describe SpecGuard, "#unregister" do
  before :each do
    allow(MSpec).to receive(:unregister)
    @guard = SpecGuard.new
  end

  it "unregisters from MSpec :add actions" do
    expect(MSpec).to receive(:unregister).with(:add, @guard)
    @guard.unregister
  end
end

RSpec.describe SpecGuard, "#record" do
  after :each do
    SpecGuard.clear
  end

  it "saves the name of the guarded spec under the name of the guard" do
    guard = SpecGuard.new "a", "1.8"..."1.9"
    guard.name = :named_guard
    guard.record "SomeClass#action returns true"
    expect(SpecGuard.report).to eq({
      'named_guard a, 1.8...1.9' => ["SomeClass#action returns true"]
    })
  end
end

RSpec.describe SpecGuard, ".guards" do
  it "returns an Array" do
    expect(SpecGuard.guards).to be_kind_of(Array)
  end
end

RSpec.describe SpecGuard, ".clear_guards" do
  it "resets the array to empty" do
    SpecGuard.guards << :guard
    expect(SpecGuard.guards).to eq([:guard])
    SpecGuard.clear_guards
    expect(SpecGuard.guards).to eq([])
  end
end

RSpec.describe SpecGuard, ".finish" do
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
    expect($stdout).to eq(%[

2 specs omitted by guard: named_guard a, 1.8...1.9:

SomeClass#action returns true
SomeClass#reverse returns false

])
  end
end

RSpec.describe SpecGuard, ".run_if" do
  before :each do
    @guard = SpecGuard.new
    ScratchPad.clear
  end

  it "yields if match? returns true" do
    allow(@guard).to receive(:match?).and_return(true)
    @guard.run_if(:name) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield if match? returns false" do
    allow(@guard).to receive(:match?).and_return(false)
    @guard.run_if(:name) { fail }
  end

  it "returns the result of the block if match? is true" do
    allow(@guard).to receive(:match?).and_return(true)
    expect(@guard.run_if(:name) { 42 }).to eq(42)
  end

  it "returns nil if given a block and match? is false" do
    allow(@guard).to receive(:match?).and_return(false)
    expect(@guard.run_if(:name) { 42 }).to eq(nil)
  end

  it "returns what #match? returns when no block is given" do
    allow(@guard).to receive(:match?).and_return(true)
    expect(@guard.run_if(:name)).to eq(true)
    allow(@guard).to receive(:match?).and_return(false)
    expect(@guard.run_if(:name)).to eq(false)
  end
end

RSpec.describe SpecGuard, ".run_unless" do
  before :each do
    @guard = SpecGuard.new
    ScratchPad.clear
  end

  it "yields if match? returns false" do
    allow(@guard).to receive(:match?).and_return(false)
    @guard.run_unless(:name) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield if match? returns true" do
    allow(@guard).to receive(:match?).and_return(true)
    @guard.run_unless(:name) { fail }
  end

  it "returns the result of the block if match? is false" do
    allow(@guard).to receive(:match?).and_return(false)
    expect(@guard.run_unless(:name) { 42 }).to eq(42)
  end

  it "returns nil if given a block and match? is true" do
    allow(@guard).to receive(:match?).and_return(true)
    expect(@guard.run_unless(:name) { 42 }).to eq(nil)
  end

  it "returns the opposite of what #match? returns when no block is given" do
    allow(@guard).to receive(:match?).and_return(true)
    expect(@guard.run_unless(:name)).to eq(false)
    allow(@guard).to receive(:match?).and_return(false)
    expect(@guard.run_unless(:name)).to eq(true)
  end
end

RSpec.describe Object, "#guard" do
  before :each do
    ScratchPad.clear
  end

  after :each do
    MSpec.clear_modes
  end

  it "allows to combine guards" do
    guard1 = VersionGuard.new '1.2.3', 'x.x.x'
    allow(VersionGuard).to receive(:new).and_return(guard1)
    guard2 = PlatformGuard.new :dummy
    allow(PlatformGuard).to receive(:new).and_return(guard2)

    allow(guard1).to receive(:match?).and_return(true)
    allow(guard2).to receive(:match?).and_return(true)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield
    end
    expect(ScratchPad.recorded).to eq(:yield)

    allow(guard1).to receive(:match?).and_return(false)
    allow(guard2).to receive(:match?).and_return(true)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end

    allow(guard1).to receive(:match?).and_return(true)
    allow(guard2).to receive(:match?).and_return(false)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end

    allow(guard1).to receive(:match?).and_return(false)
    allow(guard2).to receive(:match?).and_return(false)
    guard -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end
  end

  it "yields when the Proc returns true" do
    guard -> { true } do
      ScratchPad.record :yield
    end
    expect(ScratchPad.recorded).to eq(:yield)
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
    expect(ScratchPad.recorded).to eq(:yield1)

    guard -> { true } do
      ScratchPad.record :yield2
    end
    expect(ScratchPad.recorded).to eq(:yield2)
  end

  it "yields if MSpec.mode?(:verify) is true" do
    MSpec.register_mode :verify

    guard -> { false } do
      ScratchPad.record :yield1
    end
    expect(ScratchPad.recorded).to eq(:yield1)

    guard -> { true } do
      ScratchPad.record :yield2
    end
    expect(ScratchPad.recorded).to eq(:yield2)
  end

  it "yields if MSpec.mode?(:report) is true" do
    MSpec.register_mode :report

    guard -> { false } do
      ScratchPad.record :yield1
    end
    expect(ScratchPad.recorded).to eq(:yield1)

    guard -> { true } do
      ScratchPad.record :yield2
    end
    expect(ScratchPad.recorded).to eq(:yield2)
  end

  it "raises an error if no Proc is given" do
    expect { guard :foo }.to raise_error(RuntimeError)
  end

  it "requires a block" do
    expect {
      guard(-> { true })
    }.to raise_error(LocalJumpError)
    expect {
      guard(-> { false })
    }.to raise_error(LocalJumpError)
  end
end

RSpec.describe Object, "#guard_not" do
  before :each do
    ScratchPad.clear
  end

  it "allows to combine guards" do
    guard1 = VersionGuard.new '1.2.3', 'x.x.x'
    allow(VersionGuard).to receive(:new).and_return(guard1)
    guard2 = PlatformGuard.new :dummy
    allow(PlatformGuard).to receive(:new).and_return(guard2)

    allow(guard1).to receive(:match?).and_return(true)
    allow(guard2).to receive(:match?).and_return(true)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      fail
    end

    allow(guard1).to receive(:match?).and_return(false)
    allow(guard2).to receive(:match?).and_return(true)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield1
    end
    expect(ScratchPad.recorded).to eq(:yield1)

    allow(guard1).to receive(:match?).and_return(true)
    allow(guard2).to receive(:match?).and_return(false)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield2
    end
    expect(ScratchPad.recorded).to eq(:yield2)

    allow(guard1).to receive(:match?).and_return(false)
    allow(guard2).to receive(:match?).and_return(false)
    guard_not -> { ruby_version_is "2.4" and platform_is :linux } do
      ScratchPad.record :yield3
    end
    expect(ScratchPad.recorded).to eq(:yield3)
  end

  it "yields when the Proc returns false" do
    guard_not -> { false } do
      ScratchPad.record :yield
    end
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield when the Proc returns true" do
    guard_not -> { true } do
      fail
    end
  end

  it "raises an error if no Proc is given" do
    expect { guard_not :foo }.to raise_error(RuntimeError)
  end

  it "requires a block" do
    expect {
      guard_not(-> { true })
    }.to raise_error(LocalJumpError)
    expect {
      guard_not(-> { false })
    }.to raise_error(LocalJumpError)
  end
end
