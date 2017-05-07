require 'spec_helper'
require 'mspec/guards'

describe Object, "#platform_is" do
  before :each do
    @guard = PlatformGuard.new :dummy
    PlatformGuard.stub(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "does not yield when #os? returns false" do
    PlatformGuard.stub(:os?).and_return(false)
    platform_is(:ruby) { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "yields when #os? returns true" do
    PlatformGuard.stub(:os?).and_return(true)
    platform_is(:solarce) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "sets the name of the guard to :platform_is" do
    platform_is(:solarce) { }
    @guard.name.should == :platform_is
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:match?).and_return(true)
    @guard.should_receive(:unregister)
    lambda do
      platform_is(:solarce) { raise Exception }
    end.should raise_error(Exception)
  end
end

describe Object, "#platform_is_not" do
  before :each do
    @guard = PlatformGuard.new :dummy
    PlatformGuard.stub(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "does not yield when #os? returns true" do
    PlatformGuard.stub(:os?).and_return(true)
    platform_is_not(:ruby) { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end

  it "yields when #os? returns false" do
    PlatformGuard.stub(:os?).and_return(false)
    platform_is_not(:solarce) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "sets the name of the guard to :platform_is_not" do
    platform_is_not(:solarce) { }
    @guard.name.should == :platform_is_not
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    @guard.should_receive(:match?).and_return(false)
    @guard.should_receive(:unregister)
    lambda do
      platform_is_not(:solarce) { raise Exception }
    end.should raise_error(Exception)
  end
end

describe Object, "#platform_is :wordsize => SIZE_SPEC" do
  before :each do
    @guard = PlatformGuard.new :darwin, :wordsize => 32
    PlatformGuard.stub(:os?).and_return(true)
    PlatformGuard.stub(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #wordsize? returns true" do
    PlatformGuard.stub(:wordsize?).and_return(true)
    platform_is(:wordsize => 32) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "doesn not yield when #wordsize? returns false" do
    PlatformGuard.stub(:wordsize?).and_return(false)
    platform_is(:wordsize => 32) { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end
end

describe Object, "#platform_is_not :wordsize => SIZE_SPEC" do
  before :each do
    @guard = PlatformGuard.new :darwin, :wordsize => 32
    PlatformGuard.stub(:os?).and_return(true)
    PlatformGuard.stub(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #wordsize? returns false" do
    PlatformGuard.stub(:wordsize?).and_return(false)
    platform_is_not(:wordsize => 32) { ScratchPad.record :yield }
    ScratchPad.recorded.should == :yield
  end

  it "doesn not yield when #wordsize? returns true" do
    PlatformGuard.stub(:wordsize?).and_return(true)
    platform_is_not(:wordsize => 32) { ScratchPad.record :yield }
    ScratchPad.recorded.should_not == :yield
  end
end

describe PlatformGuard, ".implementation?" do
  before :all do
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  after :all do
    $VERBOSE = @verbose
  end

  before :each do
    @ruby_name = Object.const_get :RUBY_NAME
  end

  after :each do
    Object.const_set :RUBY_NAME, @ruby_name
  end

  it "returns true if passed :ruby and RUBY_NAME == 'ruby'" do
    Object.const_set :RUBY_NAME, 'ruby'
    PlatformGuard.implementation?(:ruby).should == true
  end

  it "returns true if passed :rubinius and RUBY_NAME == 'rbx'" do
    Object.const_set :RUBY_NAME, 'rbx'
    PlatformGuard.implementation?(:rubinius).should == true
  end

  it "returns true if passed :jruby and RUBY_NAME == 'jruby'" do
    Object.const_set :RUBY_NAME, 'jruby'
    PlatformGuard.implementation?(:jruby).should == true
  end

  it "returns true if passed :ironruby and RUBY_NAME == 'ironruby'" do
    Object.const_set :RUBY_NAME, 'ironruby'
    PlatformGuard.implementation?(:ironruby).should == true
  end

  it "returns true if passed :maglev and RUBY_NAME == 'maglev'" do
    Object.const_set :RUBY_NAME, 'maglev'
    PlatformGuard.implementation?(:maglev).should == true
  end

  it "returns true if passed :topaz and RUBY_NAME == 'topaz'" do
    Object.const_set :RUBY_NAME, 'topaz'
    PlatformGuard.implementation?(:topaz).should == true
  end

  it "returns true if passed :ruby and RUBY_NAME matches /^ruby/" do
    Object.const_set :RUBY_NAME, 'ruby'
    PlatformGuard.implementation?(:ruby).should == true

    Object.const_set :RUBY_NAME, 'ruby1.8'
    PlatformGuard.implementation?(:ruby).should == true

    Object.const_set :RUBY_NAME, 'ruby1.9'
    PlatformGuard.implementation?(:ruby).should == true
  end

  it "raises an error when passed an unrecognized name" do
    Object.const_set :RUBY_NAME, 'ruby'
    lambda {
      PlatformGuard.implementation?(:python)
    }.should raise_error(/unknown implementation/)
  end
end

describe PlatformGuard, ".standard?" do
  it "returns true if implementation? returns true" do
    PlatformGuard.should_receive(:implementation?).with(:ruby).and_return(true)
    PlatformGuard.standard?.should be_true
  end

  it "returns false if implementation? returns false" do
    PlatformGuard.should_receive(:implementation?).with(:ruby).and_return(false)
    PlatformGuard.standard?.should be_false
  end
end

describe PlatformGuard, ".wordsize?" do
  it "returns true when arg is 32 and 1.size is 4" do
    PlatformGuard.wordsize?(32).should == (1.size == 4)
  end

  it "returns true when arg is 64 and 1.size is 8" do
    PlatformGuard.wordsize?(64).should == (1.size == 8)
  end
end

describe PlatformGuard, ".os?" do
  before :each do
    stub_const 'PlatformGuard::HOST_OS', 'solarce'
  end

  it "returns false when arg does not match the platform" do
    PlatformGuard.os?(:ruby).should == false
  end

  it "returns false when no arg matches the platform" do
    PlatformGuard.os?(:ruby, :jruby, :rubinius, :maglev).should == false
  end

  it "returns true when arg matches the platform" do
    PlatformGuard.os?(:solarce).should == true
  end

  it "returns true when any arg matches the platform" do
    PlatformGuard.os?(:ruby, :jruby, :solarce, :rubinius, :maglev).should == true
  end

  it "returns true when arg is :windows and the platform contains 'mswin'" do
    stub_const 'PlatformGuard::HOST_OS', 'mswin32'
    PlatformGuard.os?(:windows).should == true
  end

  it "returns true when arg is :windows and the platform contains 'mingw'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mingw32'
    PlatformGuard.os?(:windows).should == true
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mswin'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mswin32'
    PlatformGuard.os?(:linux).should == false
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mingw'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mingw32'
    PlatformGuard.os?(:linux).should == false
  end
end

describe PlatformGuard, ".os? on JRuby" do
  before :all do
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  after :all do
    $VERBOSE = @verbose
  end

  before :each do
    @ruby_platform = Object.const_get :RUBY_PLATFORM
    Object.const_set :RUBY_PLATFORM, 'java'
  end

  after :each do
    Object.const_set :RUBY_PLATFORM, @ruby_platform
  end

  it "raises an error when testing for a :java platform" do
    lambda {
      PlatformGuard.os?(:java)
    }.should raise_error(":java is not a valid OS")
  end

  it "returns true when arg is :windows and RUBY_PLATFORM contains 'java' and os?(:windows) is true" do
    stub_const 'PlatformGuard::HOST_OS', 'mswin32'
    PlatformGuard.os?(:windows).should == true
  end

  it "returns true when RUBY_PLATFORM contains 'java' and os?(argument) is true" do
    stub_const 'PlatformGuard::HOST_OS', 'amiga'
    PlatformGuard.os?(:amiga).should == true
  end
end

describe PlatformGuard, ".os?" do
  before :each do
    stub_const 'PlatformGuard::HOST_OS', 'unreal'
  end

  it "returns true if argument matches RbConfig::CONFIG['host_os']" do
    PlatformGuard.os?(:unreal).should == true
  end

  it "returns true if any argument matches RbConfig::CONFIG['host_os']" do
    PlatformGuard.os?(:bsd, :unreal, :amiga).should == true
  end

  it "returns false if no argument matches RbConfig::CONFIG['host_os']" do
    PlatformGuard.os?(:bsd, :netbsd, :amiga, :msdos).should == false
  end

  it "returns false if argument does not match RbConfig::CONFIG['host_os']" do
    PlatformGuard.os?(:amiga).should == false
  end

  it "returns true when arg is :windows and RbConfig::CONFIG['host_os'] contains 'mswin'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mswin32'
    PlatformGuard.os?(:windows).should == true
  end

  it "returns true when arg is :windows and RbConfig::CONFIG['host_os'] contains 'mingw'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mingw32'
    PlatformGuard.os?(:windows).should == true
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mswin'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mingw32'
    PlatformGuard.os?(:linux).should == false
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mingw'" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mingw32'
    PlatformGuard.os?(:linux).should == false
  end
end

describe PlatformGuard, ".windows?" do
  it "returns true on windows" do
    stub_const 'PlatformGuard::HOST_OS', 'i386-mingw32'
    PlatformGuard.windows?.should == true
  end

  it "returns false on non-windows" do
    stub_const 'PlatformGuard::HOST_OS', 'i586-linux'
    PlatformGuard.windows?.should == false
  end
end
