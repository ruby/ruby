require 'spec_helper'
require 'mspec/guards'
require 'rbconfig'

describe SpecGuard, ".ruby_version" do
  before :each do
    @ruby_version = Object.const_get :RUBY_VERSION
    Object.const_set :RUBY_VERSION, "8.2.3"
  end

  after :each do
    Object.const_set :RUBY_VERSION, @ruby_version
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
