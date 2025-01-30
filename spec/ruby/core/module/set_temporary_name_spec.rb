require_relative '../../spec_helper'
require_relative 'fixtures/set_temporary_name'

ruby_version_is "3.3" do
  describe "Module#set_temporary_name" do
    it "can assign a temporary name" do
      m = Module.new
      m.name.should be_nil

      m.set_temporary_name("fake_name")
      m.name.should == "fake_name"

      m.set_temporary_name(nil)
      m.name.should be_nil
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
      -> { m.set_temporary_name("") }.should raise_error(ArgumentError, "empty class/module name")
    end

    it "can't assign a constant name as a temporary name" do
      m = Module.new
      -> { m.set_temporary_name("Object") }.should raise_error(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
    end

    it "can't assign a constant path as a temporary name" do
      m = Module.new
      -> { m.set_temporary_name("A::B") }.should raise_error(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
      -> { m.set_temporary_name("::A") }.should raise_error(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
      -> { m.set_temporary_name("::A::B") }.should raise_error(ArgumentError, "the temporary name must not be a constant path to avoid confusion")
    end

    it "can't assign name to permanent module" do
      -> { Object.set_temporary_name("fake_name") }.should raise_error(RuntimeError, "can't change permanent name")
    end

    it "can assign a temporary name to a module nested into an anonymous module" do
      m = Module.new
      module m::N; end
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/

      m::N.set_temporary_name("fake_name")
      m::N.name.should == "fake_name"

      m::N.set_temporary_name(nil)
      m::N.name.should be_nil
    end

    it "discards a temporary name when an outer anonymous module gets a permanent name" do
      m = Module.new
      module m::N; end

      m::N.set_temporary_name("fake_name")
      m::N.name.should == "fake_name"

      ModuleSpecs::SetTemporaryNameSpec::M = m
      m::N.name.should == "ModuleSpecs::SetTemporaryNameSpec::M::N"
    end

    it "can update the name when assigned to a constant" do
      m = Module.new
      m::N = Module.new
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
      m::N.set_temporary_name(nil)

      m::M = m::N
      m::M.name.should =~ /\A#<Module:0x\h+>::M\z/m
    end

    it "can reassign a temporary name repeatedly" do
      m = Module.new

      m.set_temporary_name("fake_name")
      m.name.should == "fake_name"

      m.set_temporary_name("fake_name_2")
      m.name.should == "fake_name_2"
    end

    it "does not affect a name of a module nested into an anonymous module with a temporary name" do
      m = Module.new
      m::N = Module.new
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/

      m.set_temporary_name("foo")
      m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
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
end
