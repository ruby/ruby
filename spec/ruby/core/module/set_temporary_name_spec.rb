require_relative '../../spec_helper'
require_relative 'fixtures/set_temporary_name'

describe "Module#set_temporary_name" do
  it "can assign a temporary name" do
    m = Module.new
    m.name.should == nil

    m.set_temporary_name("fake_name")
    m.name.should == "fake_name"

    m.set_temporary_name(nil)
    m.name.should == nil
  end

  it "returns self" do
    m = Module.new
    m.set_temporary_name("fake_name").should.equal? m
  end

  it "can assign a temporary name which is not a valid constant path" do
    m = Module.new

    m.set_temporary_name("name")
    m.name.should == "name"

    m.set_temporary_name("Template['foo.rb']")
    m.name.should == "Template['foo.rb']"

    m.set_temporary_name("a::B")
    m.name.should == "a::B"

    m.set_temporary_name("A::b")
    m.name.should == "A::b"

    m.set_temporary_name("A::B::")
    m.name.should == "A::B::"

    m.set_temporary_name("A::::B")
    m.name.should == "A::::B"

    m.set_temporary_name("A=")
    m.name.should == "A="
  end

  it "can't assign empty string as name" do
    m = Module.new
    -> { m.set_temporary_name("") }.should.raise(ArgumentError, "empty class/module name")
  end

  it "can't assign a constant name as a temporary name" do
    m = Module.new
    -> { m.set_temporary_name("Object") }.should.raise(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
  end

  it "can't assign a constant path as a temporary name" do
    m = Module.new
    -> { m.set_temporary_name("A::B") }.should.raise(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
    -> { m.set_temporary_name("::A") }.should.raise(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
    -> { m.set_temporary_name("::A::B") }.should.raise(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
  end

  it "can't assign name to permanent module" do
    -> { Object.set_temporary_name("fake_name") }.should.raise(RuntimeError, "can't change permanent name")
  end

  it "can assign a temporary name to a module nested into an anonymous module" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x\h+>::N\z/

    m::N.set_temporary_name("fake_name")
    m::N.name.should == "fake_name"

    m::N.set_temporary_name(nil)
    m::N.name.should == nil
  end

  it "discards a temporary name when an outer anonymous module gets a permanent name" do
    m = Module.new
    module m::N; end

    m::N.set_temporary_name("fake_name")
    m::N.name.should == "fake_name"

    ModuleSpecs::SetTemporaryNameSpec::M = m
    m::N.name.should == "ModuleSpecs::SetTemporaryNameSpec::M::N"
    ModuleSpecs::SetTemporaryNameSpec.send :remove_const, :M
  end

  it "can update the name when assigned to a constant" do
    m = Module.new
    m::N = Module.new
    m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
    m::N.set_temporary_name(nil)

    m::M = m::N
    m::M.name.should =~ /\A#<Module:0x\h+>::M\z/m
  end

  it "includes nested namespaces when assigning to a constant" do
    module ModuleSpecs::SetTemporaryNameSpec
      cls = Module.new

      cls.set_temporary_name("fake_name")
      cls.name.should == "fake_name"

      NestedModule = cls

      cls.name.should == "ModuleSpecs::SetTemporaryNameSpec::NestedModule"

      remove_const :NestedModule
    end
  end

  it "can reassign a temporary name repeatedly" do
    m = Module.new

    m.set_temporary_name("fake_name")
    m.name.should == "fake_name"

    m.set_temporary_name("fake_name_2")
    m.name.should == "fake_name_2"
  end

  ruby_bug "#21094", ""..."4.0" do
    it "also updates a name of a nested module" do
      m = Module.new
      m::N = Module.new
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/

      m.set_temporary_name "m"
      m::N.name.should == "m::N"

      m.set_temporary_name nil
      m::N.name.should == nil
    end
  end

  it "can assign a temporary name to a module nested deeper into an anonymous module" do
    m = Module.new
    module m::N; module O; end; end

    m::N::O.set_temporary_name("fake_name")
    m::N::O.name.should == "fake_name"
  end

  it "can't assign a temporary name to a module nested into a module with a permanent name" do
    m = Module.new
    module m::N; module O; end; end
    ModuleSpecs::SetTemporaryNameSpec::Permanent = m

    -> { m::N::O.set_temporary_name("fake_name") }.should.raise(RuntimeError, "can't change permanent name")
  ensure
    ModuleSpecs::SetTemporaryNameSpec.send :remove_const, :Permanent
  end

  it "updates the name of a nested module each time it is reassigned" do
    m = Module.new
    m::N = Module.new

    m.set_temporary_name "a"
    m::N.name.should == "a::N"

    m.set_temporary_name "b"
    m::N.name.should == "b::N"
  end

  it "names a nested module from the temporary name alone when nested into an anonymous module" do
    outer = Module.new
    m = Module.new
    outer::M = m
    m::N = Module.new

    m.set_temporary_name "m"
    m::N.name.should == "m::N"
  end

  it "names a nested module when an outer module gets a permanent name after its temporary name is cleared" do
    m = Module.new
    m::N = Module.new
    m.set_temporary_name nil

    ModuleSpecs::SetTemporaryNameSpec::Cleared = m
    m::N.name.should == "ModuleSpecs::SetTemporaryNameSpec::Cleared::N"
  ensure
    ModuleSpecs::SetTemporaryNameSpec.send :remove_const, :Cleared
  end

  it "discards a temporary name of a module and names the modules nested into it when an outer anonymous module gets a permanent name" do
    m = Module.new
    module m::N; module O; end; end
    m::N.set_temporary_name("fake_name")

    ModuleSpecs::SetTemporaryNameSpec::Deep = m
    m::N.name.should == "ModuleSpecs::SetTemporaryNameSpec::Deep::N"
    m::N::O.name.should == "ModuleSpecs::SetTemporaryNameSpec::Deep::N::O"
  ensure
    ModuleSpecs::SetTemporaryNameSpec.send :remove_const, :Deep
  end

  it "updates the names of nested modules that refer back to the module" do
    m = Module.new
    m::N = Module.new
    m::N::Back = m

    m.set_temporary_name "m"
    m::N.name.should == "m::N"
    m::N::Back.name.should == "m"
  end

  it "keeps temporary name when assigned in an anonymous module" do
    outer = Module.new
    m = Module.new
    m.set_temporary_name "m"
    m.name.should == "m"
    outer::M = m
    m.name.should == "m"
    m.inspect.should == "m"
  end

  it "keeps temporary name when assigned in an anonymous module and nested before" do
    outer = Module.new
    m = Module.new
    outer::A = m
    m.set_temporary_name "m"
    m.name.should == "m"
    outer::M = m
    m.name.should == "m"
    m.inspect.should == "m"
  end
end
