require_relative '../../spec_helper'

describe "Module#initialize_copy" do
  it "should retain singleton methods when duped" do
    mod = Module.new
    def mod.hello
    end
    mod.dup.methods(false).should == [:hello]
  end

  # jruby/jruby#5245, https://bugs.ruby-lang.org/issues/3461
  it "should produce a duped module with inspectable class methods" do
    mod = Module.new
    def mod.hello
    end
    mod.dup.method(:hello).inspect.should =~ /Module.*hello/
  end
end
