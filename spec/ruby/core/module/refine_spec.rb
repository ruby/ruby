require_relative '../../spec_helper'
require_relative 'fixtures/refine'

describe "Module#refine" do
  it "runs its block in an anonymous module" do
    inner_self = nil
    mod = Module.new do
      refine String do
        inner_self = self
      end
    end

    mod.should_not == inner_self
    inner_self.should be_kind_of(Module)
    inner_self.name.should == nil
  end

  it "uses the same anonymous module for future refines of the same class" do
    selves = []
    mod = Module.new do
      refine String do
        selves << self
      end
    end

    mod.module_eval do
      refine String do
        selves << self
      end
    end

    selves[0].should == selves[1]
  end

  it "adds methods defined in its block to the anonymous module's public instance methods" do
    inner_self = nil
    mod = Module.new do
      refine String do
        def blah
          "blah"
        end
        inner_self = self
      end
    end

    inner_self.public_instance_methods.should include(:blah)
  end

  it "returns created anonymous module" do
    inner_self = nil
    result = nil
    mod = Module.new do
      result = refine String do
        inner_self = self
      end
    end

    result.should == inner_self
  end

  it "raises ArgumentError if not passed an argument" do
    -> do
      Module.new do
        refine {}
      end
    end.should raise_error(ArgumentError)
  end

  it "raises TypeError if not passed a class" do
    -> do
      Module.new do
        refine("foo") {}
      end
    end.should raise_error(TypeError, "wrong argument type String (expected Class or Module)")
  end

  it "accepts a module as argument" do
    inner_self = nil
    Module.new do
      refine(Enumerable) do
        def blah
        end
        inner_self = self
      end
    end

    inner_self.public_instance_methods.should include(:blah)
  end

  it "applies refinements to the module" do
    refinement = Module.new do
      refine(Enumerable) do
        def foo?
          self.any? ? "yes" : "no"
        end
      end
    end

    foo = Class.new do
      using refinement

      def initialize(items)
        @items = items
      end

      def result
        @items.foo?
      end
    end

    foo.new([]).result.should == "no"
    foo.new([1]).result.should == "yes"
  end

  it "raises ArgumentError if not given a block" do
    -> do
      Module.new do
        refine String
      end
    end.should raise_error(ArgumentError)
  end

  it "applies refinements to calls in the refine block" do
    result = nil
    Module.new do
      refine(String) do
        def foo; "foo"; end
        result = "hello".foo
      end
    end
    result.should == "foo"
  end

  it "doesn't apply refinements outside the refine block" do
    Module.new do
      refine(String) {def foo; "foo"; end}
      -> {
        "hello".foo
      }.should raise_error(NoMethodError)
    end
  end

  it "does not apply refinements to external scopes not using the module" do
    Module.new do
      refine(String) {def foo; 'foo'; end}
    end

    -> {"hello".foo}.should raise_error(NoMethodError)
  end

  # When defining multiple refinements in the same module,
  # inside a refine block all refinements from the same
  # module are active when a refined method is called
  it "makes available all refinements from the same module" do
    refinement = Module.new do
      refine Integer do
        def to_json_format
          to_s
        end
      end

      refine Array do
        def to_json_format
          "[" + map { |i| i.to_json_format }.join(", ") + "]"
        end
      end

      refine Hash do
        def to_json_format
          "{" + map { |k, v| k.to_s.dump + ": " + v.to_json_format }.join(", ") + "}"
        end
      end
    end

    result = nil

    Module.new do
      using refinement

      result = [{1 => 2}, {3 => 4}].to_json_format
    end

    result.should == '[{"1": 2}, {"3": 4}]'
  end

  it "does not make available methods from another refinement module" do
    refinery_integer = Module.new do
      refine Integer do
        def to_json_format
          to_s
        end
      end
    end

    refinery_array = Module.new do
      refine Array do
        def to_json_format
          "[" + map { |i| i.to_json_format }.join(",") + "]"
        end
      end
    end

    result = nil

    -> {
      Module.new do
        using refinery_integer
        using refinery_array

        [1, 2].to_json_format
      end
    }.should raise_error(NoMethodError)
  end

  # method lookup:
  #   * The prepended modules from the refinement for C
  #   * The refinement for C
  #   * The included modules from the refinement for C
  #   * The prepended modules of C
  #   * C
  #   * The included modules of C
  describe "method lookup" do
    it "looks in the object singleton class first" do
      refined_class = ModuleSpecs.build_refined_class

      refinement = Module.new do
        refine refined_class do
          def foo; "foo from refinement"; end
        end
      end

      result = nil
      Module.new do
        using refinement

        obj = refined_class.new
        class << obj
          def foo; "foo from singleton class"; end
        end
        result = obj.foo
      end

      result.should == "foo from singleton class"
    end

    it "looks in later included modules of the refined module first" do
      a = Module.new do
        def foo
          "foo from A"
        end
      end

      include_me_later = Module.new do
        def foo
          "foo from IncludeMeLater"
        end
      end

      c = Class.new do
        include a
      end

      refinement = Module.new do
         refine c do; end
       end

      result = nil
      Module.new do
        using refinement
        c.include include_me_later
        result = c.new.foo
      end

      result.should == "foo from IncludeMeLater"
    end

    it "looks in the class then" do
      refined_class = ModuleSpecs.build_refined_class

      refinement = Module.new do
        refine(refined_class) { }
      end

      result = nil
      Module.new do
        using refinement
        result = refined_class.new.foo
      end

      result.should == "foo"
    end
  end


  # methods in a subclass have priority over refinements in a superclass
  it "does not override methods in subclasses" do
    refined_class = ModuleSpecs.build_refined_class

    subclass = Class.new(refined_class) do
      def foo; "foo from subclass"; end
    end

    refinement = Module.new do
      refine refined_class do
        def foo; "foo from refinement"; end
      end
    end

    result = nil
    Module.new do
      using refinement
      result = subclass.new.foo
    end

    result.should == "foo from subclass"
  end

  context "for methods accessed indirectly" do
    it "is honored by Kernel#send" do
      refined_class = ModuleSpecs.build_refined_class

      refinement = Module.new do
        refine refined_class do
          def foo; "foo from refinement"; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = refined_class.new.send :foo
      end

      result.should == "foo from refinement"
    end

    it "is honored by BasicObject#__send__" do
      refined_class = ModuleSpecs.build_refined_class

      refinement = Module.new do
        refine refined_class do
          def foo; "foo from refinement"; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = refined_class.new.__send__ :foo
      end

      result.should == "foo from refinement"
    end

    it "is honored by Symbol#to_proc" do
      refinement = Module.new do
        refine Integer do
          def to_s
            "(#{super})"
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = [1, 2, 3].map(&:to_s)
      end

      result.should == ["(1)", "(2)", "(3)"]
    end

    it "is honored by Kernel#public_send" do
      refined_class = ModuleSpecs.build_refined_class

      refinement = Module.new do
        refine refined_class do
          def foo; "foo from refinement"; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = refined_class.new.public_send :foo
      end

      result.should == "foo from refinement"
    end

    it "is honored by string interpolation" do
      refinement = Module.new do
        refine Integer do
          def to_s
            "foo"
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = "#{1}"
      end

      result.should == "foo"
    end

    it "is honored by Kernel#binding" do
      refinement = Module.new do
        refine String do
          def to_s
            "hello from refinement"
          end
        end
      end

      klass = Class.new do
        using refinement

        def foo
          "foo".to_s
        end

        def get_binding
          binding
        end
      end

      result = Kernel.eval("self.foo()", klass.new.get_binding)
      result.should == "hello from refinement"
    end

    it "is honored by Kernel#method" do
      klass = Class.new
      refinement = Module.new do
        refine klass do
          def foo; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = klass.new.method(:foo).class
      end

      result.should == Method
    end

    it "is honored by Kernel#public_method" do
      klass = Class.new
      refinement = Module.new do
        refine klass do
          def foo; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = klass.new.public_method(:foo).class
      end

      result.should == Method
    end

    it "is honored by Kernel#instance_method" do
      klass = Class.new
      refinement = Module.new do
        refine klass do
          def foo; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = klass.instance_method(:foo).class
      end

      result.should == UnboundMethod
    end

    it "is honored by Kernel#respond_to?" do
      klass = Class.new
      refinement = Module.new do
        refine klass do
          def foo; end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = klass.new.respond_to?(:foo)
      end

      result.should == true
    end

    it "is honored by &" do
      refinement = Module.new do
        refine String do
          def to_proc(*args)
            -> * { 'foo' }
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = ["hola"].map(&"upcase")
      end

      result.should == ['foo']
    end
  end

  context "when super is called in a refinement" do
    it "looks in the refined class" do
      refined_class = ModuleSpecs.build_refined_class

      refinement = Module.new do
        refine refined_class do
          def foo
            super
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = refined_class.new.foo
      end

      result.should == "foo"
    end

    # super in a method of a refinement invokes the method in the refined
    # class even if there is another refinement which has been activated
    # in the same context.
    it "looks in the refined class first if called from refined method" do
      refined_class = ModuleSpecs.build_refined_class(for_super: true)

      refinement = Module.new do
        refine refined_class do
          def foo
            [:R1]
          end
        end
      end

      refinement_with_super = Module.new do
        refine refined_class do
          def foo
            [:R2] + super
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        using refinement_with_super
        result = refined_class.new.foo
      end

      result.should == [:R2, :C]
    end

    it "looks only in the refined class even if there is another active refinement" do
      refined_class = ModuleSpecs.build_refined_class(for_super: true)

      refinement = Module.new do
        refine refined_class do
          def bar
            "you cannot see me from super because I belong to another active R"
          end
        end
      end

      refinement_with_super = Module.new do
        refine refined_class do
          def bar
            super
          end
        end
      end


      Module.new do
        using refinement
        using refinement_with_super
        -> {
          refined_class.new.bar
        }.should raise_error(NoMethodError)
      end
    end
  end

  it 'and alias aliases a method within a refinement module, but not outside it' do
    Module.new do
      using Module.new {
        refine Array do
          alias :orig_count :count
        end
      }
      [1,2].orig_count.should == 2
    end
    -> { [1,2].orig_count }.should raise_error(NoMethodError)
  end

  it 'and alias_method aliases a method within a refinement module, but not outside it' do
    Module.new do
      using Module.new {
        refine Array do
          alias_method :orig_count, :count
        end
      }
      [1,2].orig_count.should == 2
    end
    -> { [1,2].orig_count }.should raise_error(NoMethodError)
  end

  it "and instance_methods returns a list of methods including those of the refined module" do
    methods = Array.instance_methods
    methods_2 = []
    Module.new do
      refine Array do
        methods_2 = instance_methods
      end
    end
    methods.should == methods_2
  end

  # Refinements are inherited by module inclusion.
  # That is, using activates all refinements in the ancestors of the specified module.
  # Refinements in a descendant have priority over refinements in an ancestor.
  context "module inclusion" do
    it "activates all refinements from all ancestors" do
      refinement_included = Module.new do
        refine Integer do
          def to_json_format
            to_s
          end
        end
      end

      refinement = Module.new do
        include refinement_included

        refine Array do
          def to_json_format
            "[" + map { |i| i.to_s }.join(", ") + "]"
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = [5.to_json_format, [1, 2, 3].to_json_format]
      end

      result.should == ["5", "[1, 2, 3]"]
    end

    it "overrides methods of ancestors by methods in descendants" do
      refinement_included = Module.new do
        refine Integer do
          def to_json_format
            to_s
          end
        end
      end

      refinement = Module.new do
        include refinement_included

        refine Integer do
          def to_json_format
            "hello from refinement"
          end
        end
      end

      result = nil
      Module.new do
        using refinement
        result = 5.to_json_format
      end

      result.should == "hello from refinement"
    end
  end

  it 'does not list methods defined only in refinement' do
    refine_object = Module.new do
      refine Object do
        def refinement_only_method
        end
      end
    end
    spec = self
    klass = Class.new { instance_methods.should_not spec.send(:include, :refinement_only_method) }
    instance = klass.new
    instance.methods.should_not include :refinement_only_method
    instance.respond_to?(:refinement_only_method).should == false
    -> { instance.method :refinement_only_method }.should raise_error(NameError)
  end
end
