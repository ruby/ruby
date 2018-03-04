require_relative '../../spec_helper'

describe "Module#using" do
  it "imports class refinements from module into the current class/module" do
    refinement = Module.new do
      refine Integer do
        def foo; "foo"; end
      end
    end

    result = nil
    Module.new do
      using refinement
      result = 1.foo
    end

    result.should == "foo"
  end

  it "accepts module as argument" do
    refinement = Module.new do
      refine Integer do
        def foo; "foo"; end
      end
    end

    -> () {
      Module.new do
        using refinement
      end
    }.should_not raise_error
  end

  it "accepts module without refinements" do
    mod = Module.new

    -> () {
      Module.new do
        using mod
      end
    }.should_not raise_error
  end

  it "does not accept class" do
    klass = Class.new

    -> () {
      Module.new do
        using klass
      end
    }.should raise_error(TypeError)
  end

  it "raises TypeError if passed something other than module" do
    -> () {
      Module.new do
        using "foo"
      end
    }.should raise_error(TypeError)
  end

  it "returns self" do
    refinement = Module.new

    result = nil
    mod = Module.new do
      result = using refinement
    end

    result.should equal(mod)
  end

  it "works in classes too" do
    refinement = Module.new do
      refine Integer do
        def foo; "foo"; end
      end
    end

    result = nil
    Class.new do
      using refinement
      result = 1.foo
    end

    result.should == "foo"
  end

  it "raises error in method scope" do
    mod = Module.new do
      def self.foo
        using Module.new {}
      end
    end

    -> () {
      mod.foo
    }.should raise_error(RuntimeError, /Module#using is not permitted in methods/)
  end

  it "activates refinement even for existed objects" do
    result = nil

    Module.new do
      klass = Class.new do
        def foo; "foo"; end
      end

      refinement = Module.new do
        refine klass do
          def foo; "foo from refinement"; end
        end
      end

      obj = klass.new
      using refinement
      result = obj.foo
    end

    result.should == "foo from refinement"
  end

  it "activates updates when refinement reopens later" do
    result = nil

    Module.new do
      klass = Class.new do
        def foo; "foo"; end
      end

      refinement = Module.new do
        refine klass do
          def foo; "foo from refinement"; end
        end
      end

      using refinement

      refinement.class_eval do
        refine klass do
          def foo; "foo from reopened refinement"; end
        end
      end

      obj = klass.new
      result = obj.foo
    end

    result.should == "foo from reopened refinement"
  end

  describe "scope of refinement" do
    it "is active until the end of current class/module" do
      ScratchPad.record []

      Module.new do
        Class.new do
          using Module.new {
            refine String do
              def to_s; "hello from refinement"; end
            end
          }
          ScratchPad << "1".to_s
        end

        ScratchPad << "1".to_s
      end

      ScratchPad.recorded.should == ["hello from refinement", "1"]
    end

    # Refinements are lexical in scope.
    # Refinements are only active within a scope after the call to using.
    # Any code before the using statement will not have the refinement activated.
    it "is not active before the `using` call" do
      ScratchPad.record []

      Module.new do
        Class.new do
          ScratchPad << "1".to_s
          using Module.new {
            refine String do
              def to_s; "hello from refinement"; end
            end
          }
          ScratchPad << "1".to_s
        end
      end

      ScratchPad.recorded.should == ["1", "hello from refinement"]
    end

    # If you call a method that is defined outside the current scope
    # the refinement will be deactivated
    it "is not active for code defined outside the current scope" do
      result = nil

      Module.new do
        klass = Class.new do
          def foo; "foo"; end
        end

        refinement = Module.new do
          refine klass do
            def foo; "foo from refinement"; end
          end
        end

        def self.call_foo(c)
          c.foo
        end

        using refinement

        result = call_foo(klass.new)
      end

      result.should == "foo"
    end

    # If a method is defined in a scope where a refinement is active
    # the refinement will be active when the method is called.
    it "is active for method defined in a scope wherever it's called" do
      klass = Class.new do
        def foo; "foo"; end
      end

      mod = Module.new do
        refinement = Module.new do
          refine klass do
            def foo; "foo from refinement"; end
          end
        end

        using refinement

        def self.call_foo(c)
          c.foo
        end
      end

      c = klass.new
      mod.call_foo(c).should == "foo from refinement"
    end

    it "is not active if `using` call is not evaluated" do
      result = nil

      Module.new do
        if false
          using Module.new {
            refine String do
              def to_s; "hello from refinement"; end
            end
          }
        end
        result = "1".to_s
      end

      result.should == "1"
    end

    # The refinements in module are not activated automatically
    # if the class is reopened later
    it "is not active when class/module reopens" do
      refinement = Module.new do
        refine String do
          def to_s
            "hello from refinement"
          end
        end
      end

      result = []
      klass = Class.new do
        using refinement
        result << "1".to_s
      end

      klass.class_eval do
        result << "1".to_s
      end

      result.should == ["hello from refinement", "1"]
    end
  end
end
