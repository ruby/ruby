require 'spec_helper'
require 'mspec/guards'

RSpec.describe Object, "#platform_is" do
  before :each do
    @guard = PlatformGuard.new :dummy
    allow(PlatformGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "does not yield when #os? returns false" do
    allow(PlatformGuard).to receive(:os?).and_return(false)
    platform_is(:ruby) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "yields when #os? returns true" do
    allow(PlatformGuard).to receive(:os?).and_return(true)
    platform_is(:solarce) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "returns what #os? returns when no block is given" do
    allow(PlatformGuard).to receive(:os?).and_return(true)
    expect(platform_is(:solarce)).to eq(true)
    allow(PlatformGuard).to receive(:os?).and_return(false)
    expect(platform_is(:solarce)).to eq(false)
  end

  it "sets the name of the guard to :platform_is" do
    platform_is(:solarce) { }
    expect(@guard.name).to eq(:platform_is)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(true)
    expect(@guard).to receive(:unregister)
    expect do
      platform_is(:solarce) { raise Exception }
    end.to raise_error(Exception)
  end
end

RSpec.describe Object, "#platform_is_not" do
  before :each do
    @guard = PlatformGuard.new :dummy
    allow(PlatformGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "does not yield when #os? returns true" do
    allow(PlatformGuard).to receive(:os?).and_return(true)
    platform_is_not(:ruby) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end

  it "yields when #os? returns false" do
    allow(PlatformGuard).to receive(:os?).and_return(false)
    platform_is_not(:solarce) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "returns the opposite of what #os? returns when no block is given" do
    allow(PlatformGuard).to receive(:os?).and_return(true)
    expect(platform_is_not(:solarce)).to eq(false)
    allow(PlatformGuard).to receive(:os?).and_return(false)
    expect(platform_is_not(:solarce)).to eq(true)
  end

  it "sets the name of the guard to :platform_is_not" do
    platform_is_not(:solarce) { }
    expect(@guard.name).to eq(:platform_is_not)
  end

  it "calls #unregister even when an exception is raised in the guard block" do
    expect(@guard).to receive(:match?).and_return(false)
    expect(@guard).to receive(:unregister)
    expect do
      platform_is_not(:solarce) { raise Exception }
    end.to raise_error(Exception)
  end
end

RSpec.describe Object, "#platform_is :wordsize => SIZE_SPEC" do
  before :each do
    @guard = PlatformGuard.new :darwin, :wordsize => 32
    allow(PlatformGuard).to receive(:os?).and_return(true)
    allow(PlatformGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #wordsize? returns true" do
    allow(PlatformGuard).to receive(:wordsize?).and_return(true)
    platform_is(:wordsize => 32) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "doesn not yield when #wordsize? returns false" do
    allow(PlatformGuard).to receive(:wordsize?).and_return(false)
    platform_is(:wordsize => 32) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end
end

RSpec.describe Object, "#platform_is_not :wordsize => SIZE_SPEC" do
  before :each do
    @guard = PlatformGuard.new :darwin, :wordsize => 32
    allow(PlatformGuard).to receive(:os?).and_return(true)
    allow(PlatformGuard).to receive(:new).and_return(@guard)
    ScratchPad.clear
  end

  it "yields when #wordsize? returns false" do
    allow(PlatformGuard).to receive(:wordsize?).and_return(false)
    platform_is_not(:wordsize => 32) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).to eq(:yield)
  end

  it "doesn not yield when #wordsize? returns true" do
    allow(PlatformGuard).to receive(:wordsize?).and_return(true)
    platform_is_not(:wordsize => 32) { ScratchPad.record :yield }
    expect(ScratchPad.recorded).not_to eq(:yield)
  end
end

RSpec.describe PlatformGuard, ".implementation?" do
  it "returns true if passed :ruby and RUBY_ENGINE == 'ruby'" do
    stub_const 'RUBY_ENGINE', 'ruby'
    expect(PlatformGuard.implementation?(:ruby)).to eq(true)
  end

  it "returns true if passed :rubinius and RUBY_ENGINE == 'rbx'" do
    stub_const 'RUBY_ENGINE', 'rbx'
    expect(PlatformGuard.implementation?(:rubinius)).to eq(true)
  end

  it "returns true if passed :jruby and RUBY_ENGINE == 'jruby'" do
    stub_const 'RUBY_ENGINE', 'jruby'
    expect(PlatformGuard.implementation?(:jruby)).to eq(true)
  end

  it "returns true if passed :ironruby and RUBY_ENGINE == 'ironruby'" do
    stub_const 'RUBY_ENGINE', 'ironruby'
    expect(PlatformGuard.implementation?(:ironruby)).to eq(true)
  end

  it "returns true if passed :maglev and RUBY_ENGINE == 'maglev'" do
    stub_const 'RUBY_ENGINE', 'maglev'
    expect(PlatformGuard.implementation?(:maglev)).to eq(true)
  end

  it "returns true if passed :topaz and RUBY_ENGINE == 'topaz'" do
    stub_const 'RUBY_ENGINE', 'topaz'
    expect(PlatformGuard.implementation?(:topaz)).to eq(true)
  end

  it "returns true if passed :ruby and RUBY_ENGINE matches /^ruby/" do
    stub_const 'RUBY_ENGINE', 'ruby'
    expect(PlatformGuard.implementation?(:ruby)).to eq(true)

    stub_const 'RUBY_ENGINE', 'ruby1.8'
    expect(PlatformGuard.implementation?(:ruby)).to eq(true)

    stub_const 'RUBY_ENGINE', 'ruby1.9'
    expect(PlatformGuard.implementation?(:ruby)).to eq(true)
  end

  it "works for an unrecognized name" do
    stub_const 'RUBY_ENGINE', 'myrubyimplementation'
    expect(PlatformGuard.implementation?(:myrubyimplementation)).to eq(true)
    expect(PlatformGuard.implementation?(:other)).to eq(false)
  end
end

RSpec.describe PlatformGuard, ".standard?" do
  it "returns true if implementation? returns true" do
    expect(PlatformGuard).to receive(:implementation?).with(:ruby).and_return(true)
    expect(PlatformGuard.standard?).to be_truthy
  end

  it "returns false if implementation? returns false" do
    expect(PlatformGuard).to receive(:implementation?).with(:ruby).and_return(false)
    expect(PlatformGuard.standard?).to be_falsey
  end
end

RSpec.describe PlatformGuard, ".wordsize?" do
  it "returns true when arg is 32 and 1.size is 4" do
    expect(PlatformGuard.wordsize?(32)).to eq(1.size == 4)
  end

  it "returns true when arg is 64 and 1.size is 8" do
    expect(PlatformGuard.wordsize?(64)).to eq(1.size == 8)
  end
end

RSpec.describe PlatformGuard, ".os?" do
  before :each do
    stub_const 'PlatformGuard::PLATFORM', 'solarce'
  end

  it "returns false when arg does not match the platform" do
    expect(PlatformGuard.os?(:ruby)).to eq(false)
  end

  it "returns false when no arg matches the platform" do
    expect(PlatformGuard.os?(:ruby, :jruby, :rubinius, :maglev)).to eq(false)
  end

  it "returns true when arg matches the platform" do
    expect(PlatformGuard.os?(:solarce)).to eq(true)
  end

  it "returns true when any arg matches the platform" do
    expect(PlatformGuard.os?(:ruby, :jruby, :solarce, :rubinius, :maglev)).to eq(true)
  end

  it "returns true when arg is :windows and the platform contains 'mswin'" do
    stub_const 'PlatformGuard::PLATFORM', 'mswin32'
    expect(PlatformGuard.os?(:windows)).to eq(true)
  end

  it "returns true when arg is :windows and the platform contains 'mingw'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mingw32'
    expect(PlatformGuard.os?(:windows)).to eq(true)
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mswin'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mswin32'
    expect(PlatformGuard.os?(:linux)).to eq(false)
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mingw'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mingw32'
    expect(PlatformGuard.os?(:linux)).to eq(false)
  end
end

RSpec.describe PlatformGuard, ".os?" do
  it "returns true if called with the current OS or architecture" do
    os = RbConfig::CONFIG["host_os"].sub("-gnu", "")
    arch = RbConfig::CONFIG["host_arch"]
    expect(PlatformGuard.os?(os)).to eq(true)
    expect(PlatformGuard.os?(arch)).to eq(true)
    expect(PlatformGuard.os?("#{arch}-#{os}")).to eq(true)
  end
end

RSpec.describe PlatformGuard, ".os? on JRuby" do
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
    expect {
      PlatformGuard.os?(:java)
    }.to raise_error(":java is not a valid OS")
  end

  it "returns true when arg is :windows and RUBY_PLATFORM contains 'java' and os?(:windows) is true" do
    stub_const 'PlatformGuard::PLATFORM', 'mswin32'
    expect(PlatformGuard.os?(:windows)).to eq(true)
  end

  it "returns true when RUBY_PLATFORM contains 'java' and os?(argument) is true" do
    stub_const 'PlatformGuard::PLATFORM', 'amiga'
    expect(PlatformGuard.os?(:amiga)).to eq(true)
  end
end

RSpec.describe PlatformGuard, ".os?" do
  before :each do
    stub_const 'PlatformGuard::PLATFORM', 'unreal'
  end

  it "returns true if argument matches RbConfig::CONFIG['host_os']" do
    expect(PlatformGuard.os?(:unreal)).to eq(true)
  end

  it "returns true if any argument matches RbConfig::CONFIG['host_os']" do
    expect(PlatformGuard.os?(:bsd, :unreal, :amiga)).to eq(true)
  end

  it "returns false if no argument matches RbConfig::CONFIG['host_os']" do
    expect(PlatformGuard.os?(:bsd, :netbsd, :amiga, :msdos)).to eq(false)
  end

  it "returns false if argument does not match RbConfig::CONFIG['host_os']" do
    expect(PlatformGuard.os?(:amiga)).to eq(false)
  end

  it "returns true when arg is :windows and RbConfig::CONFIG['host_os'] contains 'mswin'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mswin32'
    expect(PlatformGuard.os?(:windows)).to eq(true)
  end

  it "returns true when arg is :windows and RbConfig::CONFIG['host_os'] contains 'mingw'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mingw32'
    expect(PlatformGuard.os?(:windows)).to eq(true)
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mswin'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mingw32'
    expect(PlatformGuard.os?(:linux)).to eq(false)
  end

  it "returns false when arg is not :windows and RbConfig::CONFIG['host_os'] contains 'mingw'" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mingw32'
    expect(PlatformGuard.os?(:linux)).to eq(false)
  end
end

RSpec.describe PlatformGuard, ".windows?" do
  it "returns true on windows" do
    stub_const 'PlatformGuard::PLATFORM', 'i386-mingw32'
    expect(PlatformGuard.windows?).to eq(true)
  end

  it "returns false on non-windows" do
    stub_const 'PlatformGuard::PLATFORM', 'i586-linux'
    expect(PlatformGuard.windows?).to eq(false)
  end
end
