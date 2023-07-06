require_relative '../../spec_helper'
require_relative 'fixtures/module'

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

    it "can't assign empty string as name" do
      m = Module.new
      -> { m.set_temporary_name("") }.should raise_error(ArgumentError, "empty class/module name")
    end

    it "can't assign a constant name as a temporary name" do
      m = Module.new
      -> { m.set_temporary_name("Object") }.should raise_error(ArgumentError, "name must not be valid constant name")
    end

    it "can't assign name to permanent module" do
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
  end
end
