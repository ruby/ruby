require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "main.using" do
  it "requires one Module argument" do
    -> do
      eval('using', TOPLEVEL_BINDING)
    end.should raise_error(ArgumentError)

    -> do
      eval('using "foo"', TOPLEVEL_BINDING)
    end.should raise_error(TypeError)
  end

  it "uses refinements from the given module only in the target file" do
    require_relative 'fixtures/string_refinement'
    load File.expand_path('../fixtures/string_refinement_user.rb', __FILE__)
    MainSpecs::DATA[:in_module].should == 'foo'
    MainSpecs::DATA[:toplevel].should == 'foo'
    -> do
      'hello'.foo
    end.should raise_error(NoMethodError)
  end

  it "uses refinements from the given module for method calls in the target file" do
    require_relative 'fixtures/string_refinement'
    load File.expand_path('../fixtures/string_refinement_user.rb', __FILE__)
    -> do
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

  it "raises error when called from method in wrapped script" do
    -> do
      load File.expand_path('../fixtures/using_in_method.rb', __FILE__), true
    end.should raise_error(RuntimeError)
  end

  it "raises error when called on toplevel from module" do
    -> do
      load File.expand_path('../fixtures/using_in_main.rb', __FILE__), true
    end.should raise_error(RuntimeError)
  end

  ruby_version_is "3.2" do
    it "does not raise error when wrapped with module" do
      -> do
        load File.expand_path('../fixtures/using.rb', __FILE__), true
      end.should_not raise_error
    end
  end
end
