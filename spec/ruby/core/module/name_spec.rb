require_relative '../../spec_helper'
require_relative 'fixtures/module'

describe "Module#name" do
  it "is nil for an anonymous module" do
    Module.new.name.should be_nil
  end

  it "is nil when assigned to a constant in an anonymous module" do
    m = Module.new
    m::N = Module.new
    m::N.name.should be_nil
  end

  it "is not nil for a nested module created with the module keyword" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x[0-9a-f]+>::N\z/
  end

  it "changes when the module is reachable through a constant path" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
    ModuleSpecs::Anonymous::WasAnnon = m::N
    m::N.name.should == "ModuleSpecs::Anonymous::WasAnnon"
  end

  it "is set after it is removed from a constant" do
    module ModuleSpecs
      module ModuleToRemove
      end

      mod = ModuleToRemove
      remove_const(:ModuleToRemove)
      mod.name.should == "ModuleSpecs::ModuleToRemove"
    end
  end

  it "is set after it is removed from a constant under an anonymous module" do
    m = Module.new
    module m::Child; end
    child = m::Child
    m.send(:remove_const, :Child)
    child.name.should =~ /\A#<Module:0x\h+>::Child\z/
  end

  it "is set when opened with the module keyword" do
    ModuleSpecs.name.should == "ModuleSpecs"
  end

  it "is set when a nested module is opened with the module keyword" do
    ModuleSpecs::Anonymous.name.should == "ModuleSpecs::Anonymous"
  end

  it "is set when assigning to a constant" do
    m = Module.new
    ModuleSpecs::Anonymous::A = m
    m.name.should == "ModuleSpecs::Anonymous::A"
  end

  it "is not modified when assigning to a new constant after it has been accessed" do
    m = Module.new
    ModuleSpecs::Anonymous::B = m
    m.name.should == "ModuleSpecs::Anonymous::B"
    ModuleSpecs::Anonymous::C = m
    m.name.should == "ModuleSpecs::Anonymous::B"
  end

  it "is not modified when assigned to a different anonymous module" do
    m = Module.new
    module m::M; end
    first_name = m::M.name.dup
    module m::N; end
    m::N::F = m::M
    m::M.name.should == first_name
  end

  # http://bugs.ruby-lang.org/issues/6067
  it "is set with a conditional assignment to a nested constant" do
    eval("ModuleSpecs::Anonymous::F ||= Module.new")
    ModuleSpecs::Anonymous::F.name.should == "ModuleSpecs::Anonymous::F"
  end

  it "is set with a conditional assignment to a constant" do
    module ModuleSpecs::Anonymous
      D ||= Module.new
    end
    ModuleSpecs::Anonymous::D.name.should == "ModuleSpecs::Anonymous::D"
  end

  # http://redmine.ruby-lang.org/issues/show/1833
  it "preserves the encoding in which the class was defined" do
    require fixture(__FILE__, "name")
    ModuleSpecs::NameEncoding.new.name.encoding.should == Encoding::UTF_8
  end

  it "is set when the anonymous outer module name is set" do
    m = Module.new
    m::N = Module.new
    ModuleSpecs::Anonymous::E = m
    m::N.name.should == "ModuleSpecs::Anonymous::E::N"
  end

  it "returns a mutable string" do
    ModuleSpecs.name.frozen?.should be_false
  end

  it "returns a mutable string that when mutated does not modify the original module name" do
    ModuleSpecs.name << "foo"

    ModuleSpecs.name.should == "ModuleSpecs"
  end
end
