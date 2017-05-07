require 'spec_helper'
require 'mspec/guards'

# The VersionGuard specifies a version of Ruby with a String of
# the form: v = 'major.minor.tiny'.
#
# A VersionGuard instance can be created with a single String,
# which means any version >= each component of v.
# Or, the guard can be created with a Range, a..b, or a...b,
# where a, b are of the same form as v. The meaning of the Range
# is as typically understood: a..b means v >= a and v <= b;
# a...b means v >= a and v < b.

describe VersionGuard, "#match?" do
  before :each do
    hide_deprecation_warnings
    stub_const "VersionGuard::FULL_RUBY_VERSION", SpecVersion.new('1.8.6')
  end

  it "returns true when the argument is equal to RUBY_VERSION" do
    VersionGuard.new('1.8.6').match?.should == true
  end

  it "returns true when the argument is less than RUBY_VERSION" do
    VersionGuard.new('1.8').match?.should == true
    VersionGuard.new('1.8.5').match?.should == true
  end

  it "returns false when the argument is greater than RUBY_VERSION" do
    VersionGuard.new('1.8.7').match?.should == false
    VersionGuard.new('1.9.2').match?.should == false
  end

  it "returns true when the argument range includes RUBY_VERSION" do
    VersionGuard.new('1.8.5'..'1.8.7').match?.should == true
    VersionGuard.new('1.8'..'1.9').match?.should == true
    VersionGuard.new('1.8'...'1.9').match?.should == true
    VersionGuard.new('1.8'..'1.8.6').match?.should == true
    VersionGuard.new('1.8.5'..'1.8.6').match?.should == true
    VersionGuard.new(''...'1.8.7').match?.should == true
  end

  it "returns false when the argument range does not include RUBY_VERSION" do
    VersionGuard.new('1.8.7'..'1.8.9').match?.should == false
    VersionGuard.new('1.8.4'..'1.8.5').match?.should == false
    VersionGuard.new('1.8.4'...'1.8.6').match?.should == false
    VersionGuard.new('1.8.5'...'1.8.6').match?.should == false
    VersionGuard.new(''...'1.8.6').match?.should == false
  end
end

describe Object, "#ruby_version_is" do
  before :each do
    @guard = VersionGuard.new 'x.x.x'
    VersionGuard.stub(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #match? returns true" do
    @guard.stub(:match?).and_return(true)
    ruby_version_is('x.x.x') { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "does not yield when #match? returns false" do
    @guard.stub(:match?).and_return(false)
    ruby_version_is('x.x.x') { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "sets the name of the guard to :ruby_version_is" do
    ruby_version_is("") { }
    @guard.name.should == :ruby_version_is
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:match?).and_return(true)
    @guard.should_receive(:unregister)
    lambda do
      ruby_version_is("") { raise Exception }
    end.should raise_error(Exception)
  end
end
