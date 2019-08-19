require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is "2.0.0" do
  require File.expand_path('../fixtures/classes', __FILE__)
  require File.expand_path('../fixtures/string_refinement', __FILE__)

  describe "main.using" do
    it "requires one Module argument" do
      lambda do
        eval('using', TOPLEVEL_BINDING)
      end.should raise_error(ArgumentError)

      lambda do
        eval('using "foo"', TOPLEVEL_BINDING)
      end.should raise_error(TypeError)
    end

    it "uses refinements from the given module only in the target file" do
      load File.expand_path('../fixtures/string_refinement_user.rb', __FILE__)
      MainSpecs::DATA[:in_module].should == 'foo'
      MainSpecs::DATA[:toplevel].should == 'foo'
      lambda do
        'hello'.foo
      end.should raise_error(NoMethodError)
    end

    it "uses refinements from the given module for method calls in the target file" do
      load File.expand_path('../fixtures/string_refinement_user.rb', __FILE__)
      lambda do
        'hello'.foo
      end.should raise_error(NoMethodError)
      MainSpecs.call_foo('hello').should == 'foo'
    end

    it "uses refinements from the given module in the eval string" do
      cls = MainSpecs::DATA[:cls] = Class.new {def foo; 'foo'; end}
      MainSpecs::DATA[:mod] = Module.new do
        refine(cls) do
          def foo; 'bar'; end
        end
      end
      eval(<<-EOS, TOPLEVEL_BINDING).should == 'bar'
        using MainSpecs::DATA[:mod]
        MainSpecs::DATA[:cls].new.foo
      EOS
    end

    it "does not affect methods defined before it is called" do
      cls = Class.new {def foo; 'foo'; end}
      MainSpecs::DATA[:mod] = Module.new do
        refine(cls) do
          def foo; 'bar'; end
        end
      end
      x = MainSpecs::DATA[:x] = Object.new
      eval <<-EOS, TOPLEVEL_BINDING
        x = MainSpecs::DATA[:x]
        def x.before_using(obj)
          obj.foo
        end
        using MainSpecs::DATA[:mod]
        def x.after_using(obj)
          obj.foo
        end
      EOS

      obj = cls.new
      x.before_using(obj).should == 'foo'
      x.after_using(obj).should == 'bar'
    end

    it "propagates refinements added to existing modules after it is called" do
      cls = Class.new {def foo; 'foo'; end}
      mod = MainSpecs::DATA[:mod] = Module.new do
        refine(cls) do
          def foo; 'quux'; end
        end
      end
      x = MainSpecs::DATA[:x] = Object.new
      eval <<-EOS, TOPLEVEL_BINDING
        using MainSpecs::DATA[:mod]
        x = MainSpecs::DATA[:x]
        def x.call_foo(obj)
          obj.foo
        end
        def x.call_bar(obj)
          obj.bar
        end
      EOS

      obj = cls.new
      x.call_foo(obj).should == 'quux'

      mod.module_eval do
        refine(cls) do
          def bar; 'quux'; end
        end
      end

      x.call_bar(obj).should == 'quux'
    end

    it "does not propagate refinements of new modules added after it is called" do
      cls = Class.new {def foo; 'foo'; end}
      cls2 = Class.new {def bar; 'bar'; end}
      mod = MainSpecs::DATA[:mod] = Module.new do
        refine(cls) do
          def foo; 'quux'; end
        end
      end
      x = MainSpecs::DATA[:x] = Object.new
      eval <<-EOS, TOPLEVEL_BINDING
        using MainSpecs::DATA[:mod]
        x = MainSpecs::DATA[:x]
        def x.call_foo(obj)
          obj.foo
        end
        def x.call_bar(obj)
          obj.bar
        end
      EOS

      x.call_foo(cls.new).should == 'quux'

      mod.module_eval do
        refine(cls2) do
          def bar; 'quux'; end
        end
      end

      x.call_bar(cls2.new).should == 'bar'
    end
  end
end
