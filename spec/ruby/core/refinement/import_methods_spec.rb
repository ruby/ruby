require_relative '../../spec_helper'
require_relative 'fixtures/classes'

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

      it "throws an exception when argument is not a module" do
        Module.new do
          refine String do
            -> {
              import_methods Integer
            }.should raise_error(TypeError, "wrong argument type Class (expected Module)")
          end
        end
      end

      it "imports methods from multiple modules" do
        str_utils = Module.new do
          def indent(level)
            " " * level + self
          end
        end

        str_utils_fancy = Module.new do
          def indent_star(level)
            "*" * level + self
          end
        end

        Module.new do
          refine String do
            import_methods str_utils, str_utils_fancy
            "foo".indent(3).should == "   foo"
            "foo".indent_star(3).should == "***foo"
          end
        end
      end

      it "imports a method defined in the last module if method with same name is defined in multiple modules" do
        str_utils = Module.new do
          def indent(level)
            " " * level + self
          end
        end

        str_utils_fancy = Module.new do
          def indent(level)
            "*" * level + self
          end
        end

        Module.new do
          refine String do
            import_methods str_utils, str_utils_fancy
            "foo".indent(3).should == "***foo"
          end
        end
      end

      it "still imports methods of modules listed before a module that contains method not defined in Ruby" do
        str_utils = Module.new do
          def indent(level)
            " " * level + self
          end
        end

        string_refined = Module.new do
          refine String do
            -> {
              import_methods str_utils, Kernel
            }.should raise_error(ArgumentError)
          end
        end

        Module.new do
          using string_refined
          "foo".indent(3).should == "   foo"
        end
      end
    end

    it "warns if a module includes/prepends some other module" do
      module1 = Module.new do
      end

      module2 = Module.new do
        include module1
      end

      Module.new do
        refine String do
          -> {
            import_methods module2
          }.should complain(/warning: #<Module:\w*> has ancestors, but Refinement#import_methods doesn't import their methods/)
        end
      end

      Module.new do
        refine String do
          -> {
            import_methods RefinementSpec::ModuleWithAncestors
          }.should complain(/warning: RefinementSpec::ModuleWithAncestors has ancestors, but Refinement#import_methods doesn't import their methods/)
        end
      end
    end

    it "doesn't import methods from included/prepended modules" do
      Module.new do
        refine String do
          suppress_warning { import_methods RefinementSpec::ModuleWithAncestors }
        end

        using self
        -> {
          "foo".indent(3)
        }.should raise_error(NoMethodError, /undefined method `indent' for ("foo":String|an instance of String)/)
      end
    end

    it "doesn't import any methods if one of the arguments is not a module" do
      str_utils = Module.new do
        def indent(level)
          " " * level + self
        end
      end

      string_refined = Module.new do
        refine String do
          -> {
            import_methods str_utils, Integer
          }.should raise_error(TypeError)
        end
      end

      Module.new do
        using string_refined
        -> {
          "foo".indent(3)
        }.should raise_error(NoMethodError)
      end
    end

    it "imports methods from multiple modules so that methods see other's module's methods" do
      str_utils = Module.new do
        def indent(level)
          " " * level + self
        end
      end

      str_utils_normal = Module.new do
        def indent_normal(level)
          self.indent(level)
        end
      end

      Module.new do
        refine String do
          import_methods str_utils, str_utils_normal
        end

        using self
        "foo".indent_normal(3).should == "   foo"
      end
    end

    it "imports methods from module so that methods can see each other" do
      str_utils = Module.new do
        def indent(level)
          " " * level + self
        end

        def indent_with_dot(level)
          self.indent(level) + "."
        end
      end

      Module.new do
        refine String do
          import_methods str_utils
        end

        using self
        "foo".indent_with_dot(3).should == "   foo."
      end
    end

    it "doesn't import module's class methods" do
      str_utils = Module.new do
        def self.indent(level)
          " " * level + self
        end
      end

      Module.new do
        refine String do
          import_methods str_utils
        end

        using self
        -> {
          String.indent(3)
        }.should raise_error(NoMethodError, /undefined method `indent' for (String:Class|class String)/)
      end
    end

    it "imports module methods with super" do
      class_to_refine = Class.new do
        def foo(number)
          2 * number
        end
      end

      extension = Module.new do
        def foo(number)
          super * 2
        end
      end

      refinement = Module.new do
        refine class_to_refine do
          import_methods extension
        end
      end

      Module.new do
        using refinement
        class_to_refine.new.foo(2).should == 8
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

      it "raises ArgumentError when importing methods from C extension" do
        require 'zlib'
        Module.new do
          refine String do
            -> {
              import_methods Zlib
            }.should raise_error(ArgumentError, /Can't import method which is not defined with Ruby code: Zlib#*/)
          end
        end
      end
    end
  end
end
