require_relative '../../spec_helper'
require_relative 'fixtures/module'

describe "Module#name" do
  it "is nil for an anonymous module" do
    Module.new.name.should be_nil
  end

  ruby_version_is "3.3" do
    it "can assign, reassign, and clear a temporary name in a module object" do
      m = Module.new
      m.name.should be_nil

      m.set_temporary_name("tmp-name-1")
      m.name.should == "tmp-name-1"

      m.set_temporary_name("tmp-name-2")
      m.name.should == "tmp-name-2"

      m.set_temporary_name(nil)
      m.name.should be_nil
    end

    it "can assign, reassign, and clear a temporary name in a class object" do
      c = Class.new
      c.name.should be_nil

      c.set_temporary_name("tmp-name-1")
      c.name.should == "tmp-name-1"

      c.set_temporary_name("tmp-name-2")
      c.name.should == "tmp-name-2"

      c.set_temporary_name(nil)
      c.name.should be_nil
    end

    it "returns the receiver" do
      m = Module.new
      m.set_temporary_name("foo").should equal(m)
    end

    it "can't assign empty string as name" do
      m = Module.new
      -> { m.set_temporary_name("") }.should raise_error(ArgumentError, "empty class/module name")
    end

    it "can't assign a constant name as a temporary name" do
      m = Module.new
      -> { m.set_temporary_name("Object") }.should raise_error(ArgumentError, "name must not be valid constant name")
    end

    it "can't assign a temporary name to a module with a permanent name" do
      -> { Object.set_temporary_name("fake_name") }.should raise_error(RuntimeError, "can't change permanent name")
    end

    it "can assign a temporary name to a nested module" do
      m = Module.new
      module m::N; end
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/

      m::N.set_temporary_name("fake_name")
      m::N.name.should == "fake_name"

      m::N.set_temporary_name(nil)
      m::N.name.should be_nil
    end

    it "can update the name when assigned to a constant" do
      m = Module.new
      m::N = Module.new
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
      m::N.set_temporary_name(nil)

      m::M = m::N
      m::M.name.should =~ /\A#<Module:0x\h+>::M\z/m
    end

    it "does not update the names of nested modules on temporary name reset" do
      m = Module.new
      m.set_temporary_name("foo")

      m::N = Module.new
      m::N.name.should == "foo::N"

      m.set_temporary_name("bar")
      m::N.name.should == "foo::N"

      m.set_temporary_name(nil)
      m::N.name.should == "foo::N"
    end

    it "uses a reset temporary name as prefix in further constant assignments" do
      m = Module.new
      m.set_temporary_name("foo")

      m::X = Module.new
      m::X.name.should == "foo::X"

      m.set_temporary_name("bar")
      m::Y = Module.new
      m::Y.name.should == "bar::Y"

      m.set_temporary_name(nil)
      m::Z = Module.new
      m::Z.name.should =~ /\A#<Module:0x\h+>::Z\z/
    end

    it "does not set a prefix in constant assignment for modules with a temporary name" do
      m = Module.new
      m.set_temporary_name("m")

      n = Module.new
      n.set_temporary_name("n")

      n::X = m
      n::X.name.should == "m"
    end

    it "does not set a prefix in constant assignments for modules with a permanent name" do
      m = Module.new
      m.set_temporary_name("m")

      m::K = Kernel
      m::K.name.should == "Kernel"
    end

    it "is replaced by a permanent name" do
      m = Module.new
      m.set_temporary_name("foo")

      ConstantNameToBecomePermanentName = m
      m.name.should == "ConstantNameToBecomePermanentName"
    ensure
      Object.send(:remove_const, :ConstantNameToBecomePermanentName)
    end
  end

  it "is not nil when assigned to a constant in an anonymous module" do
    m = Module.new
    m::N = Module.new
    m::N.name.should.end_with? '::N'
  end

  it "is not nil for a nested module created with the module keyword" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x[0-9a-f]+>::N\z/
  end

  it "returns nil for a singleton class" do
    Module.new.singleton_class.name.should be_nil
    String.singleton_class.name.should be_nil
    Object.new.singleton_class.name.should be_nil
  end

  it "changes when the module is reachable through a constant path" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
    ModuleSpecs::Anonymous::WasAnnon = m::N
    m::N.name.should == "ModuleSpecs::Anonymous::WasAnnon"
  end

  it "may be the repeated in different module objects" do
    m = Module.new
    n = Module.new

    suppress_warning do
      ModuleSpecs::Anonymous::SameName = m
      ModuleSpecs::Anonymous::SameName = n
    end

    m.name.should == "ModuleSpecs::Anonymous::SameName"
    n.name.should == "ModuleSpecs::Anonymous::SameName"
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

  it "is set when assigning to a constant (constant path matches outer module name)" do
    m = Module.new
    ModuleSpecs::Anonymous::A = m
    m.name.should == "ModuleSpecs::Anonymous::A"
  end

  it "is set when assigning to a constant (constant path does not match outer module name)" do
    m = Module.new
    ModuleSpecs::Anonymous::SameChild::A = m
    m.name.should == "ModuleSpecs::Anonymous::Child::A"
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

  it "is set when the anonymous outer module name is set (module in one single constant)" do
    m = Module.new
    m::N = Module.new
    ModuleSpecs::Anonymous::E = m
    m::N.name.should == "ModuleSpecs::Anonymous::E::N"
  end

  # https://bugs.ruby-lang.org/issues/19681
  it "is set when the anonymous outer module name is set (module in several constants)" do
    m = Module.new
    m::N = Module.new
    m::O = m::N
    ModuleSpecs::Anonymous::StoredInMultiplePlaces = m
    valid_names = [
      "ModuleSpecs::Anonymous::StoredInMultiplePlaces::N",
      "ModuleSpecs::Anonymous::StoredInMultiplePlaces::O"
    ]
    valid_names.should include(m::N.name) # You get one of the two, but you don't know which one.
  end

  it "returns a frozen String" do
    ModuleSpecs.name.should.frozen?
  end

  it "always returns the same String for a given Module" do
    s1 = ModuleSpecs.name
    s2 = ModuleSpecs.name
    s1.should equal(s2)
  end
end
