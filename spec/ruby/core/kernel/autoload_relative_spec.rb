require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# Specs for Kernel#autoload_relative

ruby_version_is "4.1" do
  describe "Kernel#autoload_relative" do
    before :each do
      @loaded_features = $".dup
    end

    after :each do
      $".replace @loaded_features
      # Clean up constants defined by these tests
      [:KSAutoloadRelativeA, :KSAutoloadRelativeB, :KSAutoloadRelativeC,
       :KSAutoloadRelativeE, :KSAutoloadRelativeF, :KSAutoloadRelativeG,
       :KSAutoloadRelativeH, :KSAutoloadRelativeI].each do |const|
        KernelSpecs.send(:remove_const, const) if KernelSpecs.const_defined?(const, false)
      end
      [:KSAutoloadRelativeD, :NestedTest].each do |const|
        Object.send(:remove_const, const) if Object.const_defined?(const, false)
      end
    end

    it "is a private method" do
      Kernel.should have_private_instance_method(:autoload_relative)
    end

    it "registers a file to load relative to the current file" do
      KernelSpecs.autoload_relative :KSAutoloadRelativeA, "fixtures/autoload_relative_b.rb"
      path = KernelSpecs.autoload?(:KSAutoloadRelativeA)
      path.should_not be_nil
      path.should.end_with?("autoload_relative_b.rb")
      File.exist?(path).should be_true
    end

    it "loads the file when the constant is accessed" do
      KernelSpecs.autoload_relative :KSAutoloadRelativeB, "fixtures/autoload_relative_b.rb"
      KernelSpecs::KSAutoloadRelativeB.loaded.should == :ksautoload_b
    end

    it "sets the autoload constant in the constant table" do
      KernelSpecs.autoload_relative :KSAutoloadRelativeC, "fixtures/autoload_relative_b.rb"
      KernelSpecs.should have_constant(:KSAutoloadRelativeC)
    end

    it "can autoload in instance_eval with a file context" do
      result = Object.new.instance_eval(<<-CODE, __FILE__, __LINE__)
        autoload_relative :KSAutoloadRelativeD, "fixtures/autoload_relative_d.rb"
        KSAutoloadRelativeD.loaded
      CODE
      result.should == :ksautoload_d
    end

    it "raises LoadError if called from eval without file context" do
      -> {
        eval('autoload_relative :Foo, "foo.rb"')
      }.should raise_error(LoadError, /autoload_relative called without file context/)
    end

    it "accepts both string and symbol for constant name" do
      KernelSpecs.autoload_relative :KSAutoloadRelativeE, "fixtures/autoload_relative_b.rb"
      KernelSpecs.autoload_relative "KSAutoloadRelativeF", "fixtures/autoload_relative_b.rb"

      KernelSpecs.should have_constant(:KSAutoloadRelativeE)
      KernelSpecs.should have_constant(:KSAutoloadRelativeF)
    end

    it "returns nil" do
      KernelSpecs.autoload_relative(:KSAutoloadRelativeG, "fixtures/autoload_relative_b.rb").should be_nil
    end

    it "resolves nested directory paths correctly" do
      -> {
        autoload_relative :NestedTest, "../kernel/fixtures/autoload_relative_b.rb"
        autoload?(:NestedTest)
      }.should_not raise_error
    end

    it "resolves paths starting with ./" do
      KernelSpecs.autoload_relative :KSAutoloadRelativeH, "./fixtures/autoload_relative_b.rb"
      path = KernelSpecs.autoload?(:KSAutoloadRelativeH)
      path.should_not be_nil
      path.should.end_with?("autoload_relative_b.rb")
    end

    it "ignores $LOAD_PATH and uses only relative path resolution" do
      original_load_path = $LOAD_PATH.dup
      $LOAD_PATH.clear
      begin
        KernelSpecs.autoload_relative :KSAutoloadRelativeI, "fixtures/autoload_relative_b.rb"
        path = KernelSpecs.autoload?(:KSAutoloadRelativeI)
        path.should_not be_nil
        # Should still resolve even with empty $LOAD_PATH
        File.exist?(path).should be_true
      ensure
        $LOAD_PATH.replace(original_load_path)
      end
    end

    describe "when Object is frozen" do
      it "raises a FrozenError before defining the constant" do
        ruby_exe(<<-RUBY).should include("FrozenError")
          Object.freeze
          begin
            autoload_relative :Foo, "autoload_b.rb"
          rescue => e
            puts e.class
          end
        RUBY
      end
    end
  end
end
