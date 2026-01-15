require_relative '../../spec_helper'

ruby_version_is "3.4" do
  describe "GC.config" do
    context "without arguments" do
      it "returns a hash of current settings" do
        GC.config.should be_kind_of(Hash)
      end

      it "includes the name of currently loaded GC implementation as a global key" do
        GC.config.should include(:implementation)
        GC.config[:implementation].should be_kind_of(String)
      end
    end

    context "with a hash of options" do
      it "allows to set GC implementation's options, returning the new config" do
        config = GC.config({})
        # Try to find a boolean setting to reliably test changing it.
        key, _value = config.find { |_k, v| v == true }
        skip unless key

        GC.config(key => false).should == config.merge(key => false)
        GC.config[key].should == false
        GC.config(key => true).should == config
        GC.config[key].should == true
      ensure
        GC.config(config.except(:implementation))
      end

      it "does not change settings that aren't present in the hash" do
        previous = GC.config
        GC.config({})
        GC.config.should == previous
      end

      it "ignores unknown keys" do
        previous = GC.config
        GC.config(foo: "bar")
        GC.config.should == previous
      end

      it "raises an ArgumentError if options include global keys" do
        -> { GC.config(implementation: "default") }.should raise_error(ArgumentError, 'Attempting to set read-only key "Implementation"')
      end
    end

    context "with a non-hash argument" do
      it "returns current settings if argument is nil" do
        GC.config(nil).should == GC.config
      end

      it "raises ArgumentError for all other arguments" do
        -> { GC.config([]) }.should raise_error(ArgumentError)
        -> { GC.config("default") }.should raise_error(ArgumentError)
        -> { GC.config(1) }.should raise_error(ArgumentError)
      end
    end

    guard -> { PlatformGuard.standard? && GC.config[:implementation] == "default" } do
      context "with default GC implementation on MRI" do
        before do
          @default_config = GC.config({})
        end

        after do
          GC.config(@default_config.except(:implementation))
        end

        it "includes :rgengc_allow_full_mark option, true by default" do
          GC.config.should include(:rgengc_allow_full_mark)
          GC.config[:rgengc_allow_full_mark].should be_true
        end

        it "allows to set :rgengc_allow_full_mark" do
          # This key maps truthy and falsey values to true and false.
          GC.config(rgengc_allow_full_mark: nil).should == @default_config.merge(rgengc_allow_full_mark: false)
          GC.config(rgengc_allow_full_mark: 1.23).should == @default_config.merge(rgengc_allow_full_mark: true)
        end
      end
    end
  end
end
