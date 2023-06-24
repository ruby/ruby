require_relative '../../spec_helper'

describe "Refinement#import_methods" do
  ruby_version_is "3.1" do
    context "when methods are defined in Ruby code" do
      it "imports methods" do
        str_utils = Module.new do
          def indent(level)
            " " * level + self
          end
        end

        Module.new do
          refine String do
            import_methods str_utils
            "foo".indent(3).should == "   foo"
          end
        end
      end
    end

    context "when methods are not defined in Ruby code" do
      it "raises ArgumentError" do
        Module.new do
          refine String do
            -> {
              import_methods Kernel
            }.should raise_error(ArgumentError)
          end
        end
      end
    end
  end
end
