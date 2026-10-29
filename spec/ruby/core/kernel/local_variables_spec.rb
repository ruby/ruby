require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#local_variables" do
  after :each do
    ScratchPad.clear
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:local_variables)
  end

  it "contains locals as they are added" do
    a = 1
    b = 2
    local_variables.sort.should == [:a, :b]
  end

  it "is accessible from bindings" do
    def local_var_foo
      a = 1
      b = 2
      binding
    end
    foo_binding = local_var_foo()
    res = eval("local_variables",foo_binding)
    res.sort.should == [:a, :b]
  end

  it "is accessible in eval" do
    eval "a=1; b=2; ScratchPad.record local_variables"
    ScratchPad.recorded.sort.should == [:a, :b]
  end

  it "does not include locals from outside a method" do
    a = 1
    def local_var_outer_method
      b = 2
      local_variables
    end

    local_var_outer_method.should == [:b]
  end

  it "contains the locals of the main script" do
    ruby_exe("a = 1; p local_variables").should == "[:a]\n"
  end

  it "includes only unique variable names" do
    def local_var_method
      a = 1
      1.times do |;a|
        return local_variables
      end
    end

    local_var_method.should == [:a]
  end
end

describe "Kernel.local_variables" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:local_variables)
  end
end
