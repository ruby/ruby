require 'spec_helper'
require 'mspec/guards'

RSpec.describe BugGuard, "#match? when #implementation? is 'ruby'" do
  before :all do
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  after :all do
    $VERBOSE = @verbose
  end

  before :each do
    hide_deprecation_warnings
    stub_const "VersionGuard::FULL_RUBY_VERSION", SpecVersion.new('1.8.6')
    @ruby_engine = Object.const_get :RUBY_ENGINE
    Object.const_set :RUBY_ENGINE, 'ruby'
  end

  after :each do
    Object.const_set :RUBY_ENGINE, @ruby_engine
  end

  it "returns false when version argument is less than RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8.5").match?).to eq(false)
  end

  it "returns true when version argument is equal to RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8.6").match?).to eq(true)
  end

  it "returns true when version argument is greater than RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8.7").match?).to eq(true)
  end

  it "returns true when version argument implicitly includes RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8").match?).to eq(true)
    expect(BugGuard.new("#1", "1.8.6").match?).to eq(true)
  end

  it "returns true when the argument range includes RUBY_VERSION" do
    expect(BugGuard.new("#1", '1.8.5'..'1.8.7').match?).to eq(true)
    expect(BugGuard.new("#1", '1.8'..'1.9').match?).to eq(true)
    expect(BugGuard.new("#1", '1.8'...'1.9').match?).to eq(true)
    expect(BugGuard.new("#1", '1.8'..'1.8.6').match?).to eq(true)
    expect(BugGuard.new("#1", '1.8.5'..'1.8.6').match?).to eq(true)
    expect(BugGuard.new("#1", ''...'1.8.7').match?).to eq(true)
  end

  it "returns false when the argument range does not include RUBY_VERSION" do
    expect(BugGuard.new("#1", '1.8.7'..'1.8.9').match?).to eq(false)
    expect(BugGuard.new("#1", '1.8.4'..'1.8.5').match?).to eq(false)
    expect(BugGuard.new("#1", '1.8.4'...'1.8.6').match?).to eq(false)
    expect(BugGuard.new("#1", '1.8.5'...'1.8.6').match?).to eq(false)
    expect(BugGuard.new("#1", ''...'1.8.6').match?).to eq(false)
  end

  it "returns false when MSpec.mode?(:no_ruby_bug) is true" do
    expect(MSpec).to receive(:mode?).with(:no_ruby_bug).twice.and_return(:true)
    expect(BugGuard.new("#1", "1.8.5").match?).to eq(false)
    expect(BugGuard.new("#1", "1.8").match?).to eq(false)
  end
end

RSpec.describe BugGuard, "#match? when #implementation? is not 'ruby'" do
  before :all do
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  after :all do
    $VERBOSE = @verbose
  end

  before :each do
    hide_deprecation_warnings
    @ruby_version = Object.const_get :RUBY_VERSION
    @ruby_engine = Object.const_get :RUBY_ENGINE

    Object.const_set :RUBY_VERSION, '1.8.6'
    Object.const_set :RUBY_ENGINE, 'jruby'
  end

  after :each do
    Object.const_set :RUBY_VERSION, @ruby_version
    Object.const_set :RUBY_ENGINE, @ruby_engine
  end

  it "returns false when version argument is less than RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8").match?).to eq(false)
    expect(BugGuard.new("#1", "1.8.6").match?).to eq(false)
  end

  it "returns false when version argument is equal to RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8.6").match?).to eq(false)
  end

  it "returns false when version argument is greater than RUBY_VERSION" do
    expect(BugGuard.new("#1", "1.8.7").match?).to eq(false)
  end

  it "returns false no matter if the argument range includes RUBY_VERSION" do
    expect(BugGuard.new("#1", '1.8'...'1.9').match?).to eq(false)
    expect(BugGuard.new("#1", '1.8.5'...'1.8.7').match?).to eq(false)
    expect(BugGuard.new("#1", '1.8.4'...'1.8.6').match?).to eq(false)
  end

  it "returns false when MSpec.mode?(:no_ruby_bug) is true" do
    allow(MSpec).to receive(:mode?).and_return(:true)
    expect(BugGuard.new("#1", "1.8.6").match?).to eq(false)
  end
end

RSpec.describe Object, "#ruby_bug" do
  before :each do
    hide_deprecation_warnings
    @guard = BugGuard.new "#1234", "x.x.x"
    allow(BugGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #match? returns false" do
    allow(@guard).to receive(:match?).and_return(false)
    ruby_bug("#1234", "1.8.6") { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "does not yield when #match? returns true" do
    allow(@guard).to receive(:match?).and_return(true)
    ruby_bug("#1234", "1.8.6") { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "requires a bug tracker number and a version number" do
    expect { ruby_bug { }          }.to raise_error(ArgumentError)
    expect { ruby_bug("#1234") { } }.to raise_error(ArgumentError)
  end

  it "sets the name of the guard to :ruby_bug" do
    ruby_bug("#1234", "1.8.6") { }
    expect(@guard.name).to eq(:ruby_bug)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:unregister)
    expect do
      ruby_bug("", "") { raise Exception }
    end.to raise_error(Exception)
  end
end
