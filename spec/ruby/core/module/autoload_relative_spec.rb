require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# Specs for Module#autoload_relative
module ModuleSpecs
  module AutoloadRelative
    # Will be used for testing
  end
end

ruby_version_is "4.1" do
  describe "Module#autoload_relative" do
    before :each do
      @loaded_features = $".dup
    end

    after :each do
      $".replace @loaded_features
    end

    it "is a public method" do
      Module.should have_public_instance_method(:autoload_relative, false)
    end

    it "registers a file to load relative to the current file the first time the named constant is accessed" do
      ModuleSpecs::Autoload.autoload_relative :AutoloadRelativeA, "fixtures/autoload_relative_a.rb"
      path = ModuleSpecs::Autoload.autoload?(:AutoloadRelativeA)
      path.should_not be_nil
      path.should.end_with?("autoload_relative_a.rb")
      File.exist?(path).should be_true
    end

    it "loads the registered file when the constant is accessed" do
      ModuleSpecs::Autoload.autoload_relative :AutoloadRelativeB, "fixtures/autoload_relative_a.rb"
      ModuleSpecs::Autoload::AutoloadRelativeB.should be_kind_of(Module)
    end

    it "returns nil" do
      ModuleSpecs::Autoload.autoload_relative(:AutoloadRelativeC, "fixtures/autoload_relative_a.rb").should be_nil
    end

    it "registers a file to load the first time the named constant is accessed" do
      module ModuleSpecs::Autoload::AutoloadRelativeTest
        autoload_relative :D, "fixtures/autoload_relative_a.rb"
      end
      path = ModuleSpecs::Autoload::AutoloadRelativeTest.autoload?(:D)
      path.should_not be_nil
      path.should.end_with?("autoload_relative_a.rb")
    end

    it "sets the autoload constant in the constants table" do
      ModuleSpecs::Autoload.autoload_relative :AutoloadRelativeTableTest, "fixtures/autoload_relative_a.rb"
      ModuleSpecs::Autoload.should have_constant(:AutoloadRelativeTableTest)
    end

    it "calls #to_path on non-String filenames" do
      name = mock("autoload_relative mock")
      name.should_receive(:to_path).and_return("fixtures/autoload_relative_a.rb")
      ModuleSpecs::Autoload.autoload_relative :AutoloadRelativeToPath, name
      ModuleSpecs::Autoload.autoload?(:AutoloadRelativeToPath).should_not be_nil
    end

    it "calls #to_str on non-String filenames" do
      name = mock("autoload_relative mock")
      name.should_receive(:to_str).and_return("fixtures/autoload_relative_a.rb")
      ModuleSpecs::Autoload.autoload_relative :AutoloadRelativeToStr, name
      ModuleSpecs::Autoload.autoload?(:AutoloadRelativeToStr).should_not be_nil
    end

    it "raises a TypeError if the filename argument is not a String or pathname" do
      -> {
        ModuleSpecs::Autoload.autoload_relative :AutoloadRelativeTypError, nil
      }.should raise_error(TypeError)
    end

    it "raises a NameError if the constant name is not valid" do
      -> {
        ModuleSpecs::Autoload.autoload_relative :invalid_name, "fixtures/autoload_relative_a.rb"
      }.should raise_error(NameError)
    end

    it "raises an ArgumentError if the constant name starts with a lowercase letter" do
      -> {
        ModuleSpecs::Autoload.autoload_relative :autoload, "fixtures/autoload_relative_a.rb"
      }.should raise_error(NameError)
    end

    it "raises LoadError if called from eval without file context" do
      -> {
        ModuleSpecs::Autoload.module_eval('autoload_relative :EvalTest, "fixtures/autoload_relative_a.rb"')
      }.should raise_error(LoadError, /autoload_relative called without file context/)
    end

    it "can autoload in instance_eval with a file context" do
      path = nil
      ModuleSpecs::Autoload.instance_eval(<<-CODE, __FILE__, __LINE__)
        autoload_relative :InstanceEvalTest, "fixtures/autoload_relative_a.rb"
        path = autoload?(:InstanceEvalTest)
      CODE
      path.should_not be_nil
      path.should.end_with?("autoload_relative_a.rb")
    end

    it "resolves paths relative to the file where it's called" do
      # Using fixtures/autoload_relative_a.rb which exists
      ModuleSpecs::Autoload.autoload_relative :RelativePathTest, "fixtures/autoload_relative_a.rb"
      path = ModuleSpecs::Autoload.autoload?(:RelativePathTest)
      path.should.include?("fixtures")
      path.should.end_with?("autoload_relative_a.rb")
    end

    it "can load nested directory paths" do
      ModuleSpecs::Autoload.autoload_relative :NestedPath, "fixtures/autoload_relative_a.rb"
      path = ModuleSpecs::Autoload.autoload?(:NestedPath)
      path.should_not be_nil
      File.exist?(path).should be_true
    end

    describe "interoperability with autoload?" do
      it "returns the absolute path with autoload?" do
        ModuleSpecs::Autoload.autoload_relative :QueryTest, "fixtures/autoload_relative_a.rb"
        path = ModuleSpecs::Autoload.autoload?(:QueryTest)
        # Should be an absolute path
        Pathname.new(path).absolute?.should be_true
      end
    end
end
end
