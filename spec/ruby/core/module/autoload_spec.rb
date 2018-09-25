require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require 'thread'

describe "Module#autoload?" do
  it "returns the name of the file that will be autoloaded" do
    ModuleSpecs::Autoload.autoload :Autoload, "autoload.rb"
    ModuleSpecs::Autoload.autoload?(:Autoload).should == "autoload.rb"
  end

  it "returns nil if no file has been registered for a constant" do
    ModuleSpecs::Autoload.autoload?(:Manualload).should be_nil
  end
end

describe "Module#autoload" do
  before :all do
    @non_existent = fixture __FILE__, "no_autoload.rb"
  end

  before :each do
    @loaded_features = $".dup
    @frozen_module = Module.new.freeze

    ScratchPad.clear
  end

  after :each do
    $".replace @loaded_features
  end

  it "registers a file to load the first time the named constant is accessed" do
    ModuleSpecs::Autoload.autoload :A, @non_existent
    ModuleSpecs::Autoload.autoload?(:A).should == @non_existent
  end

  it "sets the autoload constant in the constants table" do
    ModuleSpecs::Autoload.autoload :B, @non_existent
    ModuleSpecs::Autoload.should have_constant(:B)
  end

  it "loads the registered constant when it is accessed" do
    ModuleSpecs::Autoload.should_not have_constant(:X)
    ModuleSpecs::Autoload.autoload :X, fixture(__FILE__, "autoload_x.rb")
    ModuleSpecs::Autoload::X.should == :x
    ModuleSpecs::Autoload.send(:remove_const, :X)
  end

  it "loads the registered constant into a dynamically created class" do
    cls = Class.new { autoload :C, fixture(__FILE__, "autoload_c.rb") }
    ModuleSpecs::Autoload::DynClass = cls

    ScratchPad.recorded.should be_nil
    ModuleSpecs::Autoload::DynClass::C.new.loaded.should == :dynclass_c
    ScratchPad.recorded.should == :loaded
  end

  it "loads the registered constant into a dynamically created module" do
    mod = Module.new { autoload :D, fixture(__FILE__, "autoload_d.rb") }
    ModuleSpecs::Autoload::DynModule = mod

    ScratchPad.recorded.should be_nil
    ModuleSpecs::Autoload::DynModule::D.new.loaded.should == :dynmodule_d
    ScratchPad.recorded.should == :loaded
  end

  it "loads the registered constant when it is opened as a class" do
    ModuleSpecs::Autoload.autoload :E, fixture(__FILE__, "autoload_e.rb")
    class ModuleSpecs::Autoload::E
    end
    ModuleSpecs::Autoload::E.new.loaded.should == :autoload_e
  end

  it "loads the registered constant when it is opened as a module" do
    ModuleSpecs::Autoload.autoload :F, fixture(__FILE__, "autoload_f.rb")
    module ModuleSpecs::Autoload::F
    end
    ModuleSpecs::Autoload::F.loaded.should == :autoload_f
  end

  it "loads the registered constant when it is inherited from" do
    ModuleSpecs::Autoload.autoload :G, fixture(__FILE__, "autoload_g.rb")
    class ModuleSpecs::Autoload::Gsub < ModuleSpecs::Autoload::G
    end
    ModuleSpecs::Autoload::Gsub.new.loaded.should == :autoload_g
  end

  it "loads the registered constant when it is included" do
    ModuleSpecs::Autoload.autoload :H, fixture(__FILE__, "autoload_h.rb")
    class ModuleSpecs::Autoload::HClass
      include ModuleSpecs::Autoload::H
    end
    ModuleSpecs::Autoload::HClass.new.loaded.should == :autoload_h
  end

  it "does not load the file when the constant is already set" do
    ModuleSpecs::Autoload.autoload :I, fixture(__FILE__, "autoload_i.rb")
    ModuleSpecs::Autoload.const_set :I, 3
    ModuleSpecs::Autoload::I.should == 3
    ScratchPad.recorded.should be_nil
  end

  it "loads a file with .rb extension when passed the name without the extension" do
    ModuleSpecs::Autoload.autoload :J, fixture(__FILE__, "autoload_j")
    ModuleSpecs::Autoload::J.should == :autoload_j
  end

  it "calls main.require(path) to load the file" do
    ModuleSpecs::Autoload.autoload :ModuleAutoloadCallsRequire, "module_autoload_not_exist.rb"
    main = TOPLEVEL_BINDING.eval("self")
    main.should_receive(:require).with("module_autoload_not_exist.rb")
    # The constant won't be defined since require is mocked to do nothing
    -> { ModuleSpecs::Autoload::ModuleAutoloadCallsRequire }.should raise_error(NameError)
  end

  it "does not load the file if the file is manually required" do
    filename = fixture(__FILE__, "autoload_k.rb")
    ModuleSpecs::Autoload.autoload :KHash, filename

    require filename
    ScratchPad.recorded.should == :loaded
    ScratchPad.clear

    ModuleSpecs::Autoload::KHash.should be_kind_of(Class)
    ModuleSpecs::Autoload::KHash::K.should == :autoload_k
    ScratchPad.recorded.should be_nil
  end

  it "ignores the autoload request if the file is already loaded" do
    filename = fixture(__FILE__, "autoload_s.rb")

    require filename

    ScratchPad.recorded.should == :loaded
    ScratchPad.clear

    ModuleSpecs::Autoload.autoload :S, filename
    ModuleSpecs::Autoload.autoload?(:S).should be_nil
    ModuleSpecs::Autoload.send(:remove_const, :S)
  end

  it "retains the autoload even if the request to require fails" do
    filename = fixture(__FILE__, "a_path_that_should_not_exist.rb")

    ModuleSpecs::Autoload.autoload :NotThere, filename
    ModuleSpecs::Autoload.autoload?(:NotThere).should == filename

    lambda {
      require filename
    }.should raise_error(LoadError)

    ModuleSpecs::Autoload.autoload?(:NotThere).should == filename
  end

  it "allows multiple autoload constants for a single file" do
    filename = fixture(__FILE__, "autoload_lm.rb")
    ModuleSpecs::Autoload.autoload :L, filename
    ModuleSpecs::Autoload.autoload :M, filename
    ModuleSpecs::Autoload::L.should == :autoload_l
    ModuleSpecs::Autoload::M.should == :autoload_m
  end

  it "runs for an exception condition class and doesn't trample the exception" do
    filename = fixture(__FILE__, "autoload_ex1.rb")
    ModuleSpecs::Autoload.autoload :EX1, filename
    ModuleSpecs::Autoload.use_ex1.should == :good
  end

  describe "interacting with defined?" do
    it "does not load the file when referring to the constant in defined?" do
      module ModuleSpecs::Autoload::Dog
        autoload :R, fixture(__FILE__, "autoload_exception.rb")
      end

      defined?(ModuleSpecs::Autoload::Dog::R).should == "constant"
      ScratchPad.recorded.should be_nil

      ModuleSpecs::Autoload::Dog.should have_constant(:R)
    end

    it "loads an autoloaded parent when referencing a nested constant" do
      module ModuleSpecs::Autoload
        autoload :GoodParent, fixture(__FILE__, "autoload_nested.rb")
      end

      defined?(ModuleSpecs::Autoload::GoodParent::Nested).should == 'constant'
      ScratchPad.recorded.should == :loaded

      ModuleSpecs::Autoload.send(:remove_const, :GoodParent)
    end

    it "returns nil when it fails to load an autoloaded parent when referencing a nested constant" do
      module ModuleSpecs::Autoload
        autoload :BadParent, fixture(__FILE__, "autoload_exception.rb")
      end

      defined?(ModuleSpecs::Autoload::BadParent::Nested).should be_nil
      ScratchPad.recorded.should == :exception
    end
  end

  describe "the autoload is removed when the same file is required directly without autoload" do
    before :each do
      module ModuleSpecs::Autoload
        autoload :RequiredDirectly, fixture(__FILE__, "autoload_required_directly.rb")
      end
      @path = fixture(__FILE__, "autoload_required_directly.rb")
      @check = -> {
        [
          defined?(ModuleSpecs::Autoload::RequiredDirectly),
          ModuleSpecs::Autoload.autoload?(:RequiredDirectly)
        ]
      }
      ScratchPad.record @check
    end

    after :each do
      ModuleSpecs::Autoload.send(:remove_const, :RequiredDirectly)
    end

    it "with a full path" do
      @check.call.should == ["constant", @path]
      require @path
      ScratchPad.recorded.should == [nil, nil]
      @check.call.should == ["constant", nil]
    end

    it "with a relative path" do
      @check.call.should == ["constant", @path]
      $:.push File.dirname(@path)
      begin
        require "autoload_required_directly.rb"
      ensure
        $:.pop
      end
      ScratchPad.recorded.should == [nil, nil]
      @check.call.should == ["constant", nil]
    end

    it "in a nested require" do
      nested = fixture(__FILE__, "autoload_required_directly_nested.rb")
      nested_require = -> {
        result = nil
        ScratchPad.record -> {
          result = [@check.call, Thread.new { @check.call }.value]
        }
        require nested
        result
      }
      ScratchPad.record nested_require

      @check.call.should == ["constant", @path]
      require @path
      cur, other = ScratchPad.recorded
      cur.should == [nil, nil]
      other.should == [nil, nil]
      @check.call.should == ["constant", nil]
    end
  end

  describe "during the autoload before the constant is assigned" do
    before :each do
      @path = fixture(__FILE__, "autoload_during_autoload.rb")
      ModuleSpecs::Autoload.autoload :DuringAutoload, @path
      raise unless ModuleSpecs::Autoload.autoload?(:DuringAutoload) == @path
    end

    after :each do
      ModuleSpecs::Autoload.send(:remove_const, :DuringAutoload)
    end

    def check_before_during_thread_after(&check)
      before = check.call
      to_autoload_thread, from_autoload_thread = Queue.new, Queue.new
      ScratchPad.record -> {
        from_autoload_thread.push check.call
        to_autoload_thread.pop
      }
      t = Thread.new {
        in_loading_thread = from_autoload_thread.pop
        in_other_thread = check.call
        to_autoload_thread.push :done
        [in_loading_thread, in_other_thread]
      }
      in_loading_thread, in_other_thread = nil
      begin
        ModuleSpecs::Autoload::DuringAutoload
      ensure
        in_loading_thread, in_other_thread = t.value
      end
      after = check.call
      [before, in_loading_thread, in_other_thread, after]
    end

    it "returns nil in autoload thread and 'constant' otherwise for defined?" do
      results = check_before_during_thread_after {
        defined?(ModuleSpecs::Autoload::DuringAutoload)
      }
      results.should == ['constant', nil, 'constant', 'constant']
    end

    it "keeps the constant in Module#constants" do
      results = check_before_during_thread_after {
        ModuleSpecs::Autoload.constants(false).include?(:DuringAutoload)
      }
      results.should == [true, true, true, true]
    end

    it "returns false in autoload thread and true otherwise for Module#const_defined?" do
      results = check_before_during_thread_after {
        ModuleSpecs::Autoload.const_defined?(:DuringAutoload, false)
      }
      results.should == [true, false, true, true]
    end

    it "returns nil in autoload thread and returns the path in other threads for Module#autoload?" do
      results = check_before_during_thread_after {
        ModuleSpecs::Autoload.autoload?(:DuringAutoload)
      }
      results.should == [@path, nil, @path, nil]
    end
  end

  it "does not remove the constant from Module#constants if load fails and keeps it as an autoload" do
    ModuleSpecs::Autoload.autoload :Fail, @non_existent

    ModuleSpecs::Autoload.const_defined?(:Fail).should == true
    ModuleSpecs::Autoload.should have_constant(:Fail)
    ModuleSpecs::Autoload.autoload?(:Fail).should == @non_existent

    lambda { ModuleSpecs::Autoload::Fail }.should raise_error(LoadError)

    ModuleSpecs::Autoload.should have_constant(:Fail)
    ModuleSpecs::Autoload.const_defined?(:Fail).should == true
    ModuleSpecs::Autoload.autoload?(:Fail).should == @non_existent

    lambda { ModuleSpecs::Autoload::Fail }.should raise_error(LoadError)
  end

  it "does not remove the constant from Module#constants if load raises a RuntimeError and keeps it as an autoload" do
    path = fixture(__FILE__, "autoload_raise.rb")
    ScratchPad.record []
    ModuleSpecs::Autoload.autoload :Raise, path

    ModuleSpecs::Autoload.const_defined?(:Raise).should == true
    ModuleSpecs::Autoload.should have_constant(:Raise)
    ModuleSpecs::Autoload.autoload?(:Raise).should == path

    lambda { ModuleSpecs::Autoload::Raise }.should raise_error(RuntimeError)
    ScratchPad.recorded.should == [:raise]

    ModuleSpecs::Autoload.should have_constant(:Raise)
    ModuleSpecs::Autoload.const_defined?(:Raise).should == true
    ModuleSpecs::Autoload.autoload?(:Raise).should == path

    lambda { ModuleSpecs::Autoload::Raise }.should raise_error(RuntimeError)
    ScratchPad.recorded.should == [:raise, :raise]
  end

  it "does not remove the constant from Module#constants if the loaded file does not define it, but leaves it as 'undefined'" do
    path = fixture(__FILE__, "autoload_o.rb")
    ScratchPad.record []
    ModuleSpecs::Autoload.autoload :O, path

    ModuleSpecs::Autoload.const_defined?(:O).should == true
    ModuleSpecs::Autoload.should have_constant(:O)
    ModuleSpecs::Autoload.autoload?(:O).should == path

    lambda { ModuleSpecs::Autoload::O }.should raise_error(NameError)

    ModuleSpecs::Autoload.should have_constant(:O)
    ModuleSpecs::Autoload.const_defined?(:O).should == false
    ModuleSpecs::Autoload.autoload?(:O).should == nil
    -> { ModuleSpecs::Autoload.const_get(:O) }.should raise_error(NameError)
  end

  it "does not try to load the file again if the loaded file did not define the constant" do
    path = fixture(__FILE__, "autoload_o.rb")
    ScratchPad.record []
    ModuleSpecs::Autoload.autoload :NotDefinedByFile, path

    -> { ModuleSpecs::Autoload::NotDefinedByFile }.should raise_error(NameError)
    ScratchPad.recorded.should == [:loaded]
    -> { ModuleSpecs::Autoload::NotDefinedByFile }.should raise_error(NameError)
    ScratchPad.recorded.should == [:loaded]

    Thread.new {
      -> { ModuleSpecs::Autoload::NotDefinedByFile }.should raise_error(NameError)
    }.join
    ScratchPad.recorded.should == [:loaded]
  end

  it "returns 'constant' on referring the constant with defined?()" do
    module ModuleSpecs::Autoload::Q
      autoload :R, fixture(__FILE__, "autoload.rb")
      defined?(R).should == 'constant'
    end
    ModuleSpecs::Autoload::Q.should have_constant(:R)
  end

  it "does not load the file when removing an autoload constant" do
    module ModuleSpecs::Autoload::Q
      autoload :R, fixture(__FILE__, "autoload.rb")
      remove_const :R
    end
    ModuleSpecs::Autoload::Q.should_not have_constant(:R)
  end

  it "does not load the file when accessing the constants table of the module" do
    ModuleSpecs::Autoload.autoload :P, @non_existent
    ModuleSpecs::Autoload.const_defined?(:P).should be_true
  end

  it "loads the file when opening a module that is the autoloaded constant" do
    module ModuleSpecs::Autoload::U
      autoload :V, fixture(__FILE__, "autoload_v.rb")

      class V
        X = get_value
      end
    end

    ModuleSpecs::Autoload::U::V::X.should == :autoload_uvx
  end

  it "loads the file that defines subclass XX::YY < YY and YY is a top level constant" do
    module ModuleSpecs::Autoload::XX
      autoload :YY, fixture(__FILE__, "autoload_subclass.rb")
    end

    ModuleSpecs::Autoload::XX::YY.superclass.should == YY
  end

  describe "after autoloading searches for the constant like the original lookup" do
    it "in lexical scopes if both declared and defined in parent" do
      module ModuleSpecs::Autoload
        ScratchPad.record -> {
          DeclaredAndDefinedInParent = :declared_and_defined_in_parent
        }
        autoload :DeclaredAndDefinedInParent, fixture(__FILE__, "autoload_callback.rb")
        class LexicalScope
          DeclaredAndDefinedInParent.should == :declared_and_defined_in_parent

          # The constant is really in Autoload, not Autoload::LexicalScope
          self.should_not have_constant(:DeclaredAndDefinedInParent)
          -> { const_get(:DeclaredAndDefinedInParent) }.should raise_error(NameError)
        end
        DeclaredAndDefinedInParent.should == :declared_and_defined_in_parent
      end
    end

    it "in lexical scopes if declared in parent and defined in current" do
      module ModuleSpecs::Autoload
        ScratchPad.record -> {
          class LexicalScope
            DeclaredInParentDefinedInCurrent = :declared_in_parent_defined_in_current
          end
        }
        autoload :DeclaredInParentDefinedInCurrent, fixture(__FILE__, "autoload_callback.rb")

        class LexicalScope
          DeclaredInParentDefinedInCurrent.should == :declared_in_parent_defined_in_current
          LexicalScope::DeclaredInParentDefinedInCurrent.should == :declared_in_parent_defined_in_current
        end

        # Basically, the parent autoload constant remains in a "undefined" state
        self.autoload?(:DeclaredInParentDefinedInCurrent).should == nil
        const_defined?(:DeclaredInParentDefinedInCurrent).should == false
        self.should have_constant(:DeclaredInParentDefinedInCurrent)
        -> { DeclaredInParentDefinedInCurrent }.should raise_error(NameError)

        ModuleSpecs::Autoload::LexicalScope.send(:remove_const, :DeclaredInParentDefinedInCurrent)
      end
    end

    it "and fails when finding the undefined autoload constant in the the current scope when declared in current and defined in parent" do
      module ModuleSpecs::Autoload
        ScratchPad.record -> {
          DeclaredInCurrentDefinedInParent = :declared_in_current_defined_in_parent
        }

        class LexicalScope
          autoload :DeclaredInCurrentDefinedInParent, fixture(__FILE__, "autoload_callback.rb")
          -> { DeclaredInCurrentDefinedInParent }.should raise_error(NameError)
          # Basically, the autoload constant remains in a "undefined" state
          self.autoload?(:DeclaredInCurrentDefinedInParent).should == nil
          const_defined?(:DeclaredInCurrentDefinedInParent).should == false
          self.should have_constant(:DeclaredInCurrentDefinedInParent)
          -> { const_get(:DeclaredInCurrentDefinedInParent) }.should raise_error(NameError)
        end

        DeclaredInCurrentDefinedInParent.should == :declared_in_current_defined_in_parent
      end
    end

    it "in the included modules" do
      module ModuleSpecs::Autoload
        ScratchPad.record -> {
          module DefinedInIncludedModule
            Incl = :defined_in_included_module
          end
          include DefinedInIncludedModule
        }
        autoload :Incl, fixture(__FILE__, "autoload_callback.rb")
        Incl.should == :defined_in_included_module
      end
    end

    it "in the included modules of the superclass" do
      module ModuleSpecs::Autoload
        class LookupAfterAutoloadSuper
        end
        class LookupAfterAutoloadChild < LookupAfterAutoloadSuper
        end

        ScratchPad.record -> {
          module DefinedInSuperclassIncludedModule
            InclS = :defined_in_superclass_included_module
          end
          LookupAfterAutoloadSuper.include DefinedInSuperclassIncludedModule
        }

        class LookupAfterAutoloadChild
          autoload :InclS, fixture(__FILE__, "autoload_callback.rb")
          InclS.should == :defined_in_superclass_included_module
        end
      end
    end

    it "in the prepended modules" do
      module ModuleSpecs::Autoload
        ScratchPad.record -> {
          module DefinedInPrependedModule
            Prep = :defined_in_prepended_module
          end
          include DefinedInPrependedModule
        }
        autoload :Prep, fixture(__FILE__, "autoload_callback.rb")
        Prep.should == :defined_in_prepended_module
      end
    end

    it "in a meta class scope" do
      module ModuleSpecs::Autoload
        ScratchPad.record -> {
          class MetaScope
          end
        }
        autoload :MetaScope, fixture(__FILE__, "autoload_callback.rb")
        class << self
          def r
            MetaScope.new
          end
        end
      end
      ModuleSpecs::Autoload.r.should be_kind_of(ModuleSpecs::Autoload::MetaScope)
    end
  end

  # [ruby-core:19127] [ruby-core:29941]
  it "does NOT raise a NameError when the autoload file did not define the constant and a module is opened with the same name" do
    module ModuleSpecs::Autoload
      class W
        autoload :Y, fixture(__FILE__, "autoload_w.rb")

        class Y
        end
      end
    end

    ModuleSpecs::Autoload::W::Y.should be_kind_of(Class)
    ScratchPad.recorded.should == :loaded
    ModuleSpecs::Autoload::W.send(:remove_const, :Y)
  end

  it "does not call #require a second time and does not warn if already loading the same feature with #require" do
    main = TOPLEVEL_BINDING.eval("self")
    main.should_not_receive(:require)

    module ModuleSpecs::Autoload
      autoload :AutoloadDuringRequire, fixture(__FILE__, "autoload_during_require.rb")
    end

    -> {
      $VERBOSE = true
      Kernel.require fixture(__FILE__, "autoload_during_require.rb")
    }.should_not complain
    ModuleSpecs::Autoload::AutoloadDuringRequire.should be_kind_of(Class)
  end

  it "calls #to_path on non-string filenames" do
    p = mock('path')
    p.should_receive(:to_path).and_return @non_existent
    ModuleSpecs.autoload :A, p
  end

  it "raises an ArgumentError when an empty filename is given" do
    lambda { ModuleSpecs.autoload :A, "" }.should raise_error(ArgumentError)
  end

  it "raises a NameError when the constant name starts with a lower case letter" do
    lambda { ModuleSpecs.autoload "a", @non_existent }.should raise_error(NameError)
  end

  it "raises a NameError when the constant name starts with a number" do
    lambda { ModuleSpecs.autoload "1two", @non_existent }.should raise_error(NameError)
  end

  it "raises a NameError when the constant name has a space in it" do
    lambda { ModuleSpecs.autoload "a name", @non_existent }.should raise_error(NameError)
  end

  it "shares the autoload request across dup'ed copies of modules" do
    require fixture(__FILE__, "autoload_s.rb")
    filename = fixture(__FILE__, "autoload_t.rb")
    mod1 = Module.new { autoload :T, filename }
    lambda {
      ModuleSpecs::Autoload::S = mod1
    }.should complain(/already initialized constant/)
    mod2 = mod1.dup

    mod1.autoload?(:T).should == filename
    mod2.autoload?(:T).should == filename

    mod1::T.should == :autoload_t
    lambda { mod2::T }.should raise_error(NameError)
  end

  it "raises a TypeError if opening a class with a different superclass than the class defined in the autoload file" do
    ModuleSpecs::Autoload.autoload :Z, fixture(__FILE__, "autoload_z.rb")
    class ModuleSpecs::Autoload::ZZ
    end

    lambda do
      class ModuleSpecs::Autoload::Z < ModuleSpecs::Autoload::ZZ
      end
    end.should raise_error(TypeError)
  end

  it "raises a TypeError if not passed a String or object respodning to #to_path for the filename" do
    name = mock("autoload_name.rb")

    lambda { ModuleSpecs::Autoload.autoload :Str, name }.should raise_error(TypeError)
  end

  it "calls #to_path on non-String filename arguments" do
    name = mock("autoload_name.rb")
    name.should_receive(:to_path).and_return("autoload_name.rb")

    lambda { ModuleSpecs::Autoload.autoload :Str, name }.should_not raise_error
  end

  describe "on a frozen module" do
    it "raises a #{frozen_error_class} before setting the name" do
      lambda { @frozen_module.autoload :Foo, @non_existent }.should raise_error(frozen_error_class)
      @frozen_module.should_not have_constant(:Foo)
    end
  end

  describe "when changing $LOAD_PATH" do
    before do
      $LOAD_PATH.unshift(File.expand_path('../fixtures/path1', __FILE__))
    end

    after do
      $LOAD_PATH.shift
      $LOAD_PATH.shift
    end

    it "does not reload a file due to a different load path" do
      ModuleSpecs::Autoload.autoload :LoadPath, "load_path"
      ModuleSpecs::Autoload::LoadPath.loaded.should == :autoload_load_path
    end
  end

  describe "(concurrently)" do
    it "blocks a second thread while a first is doing the autoload" do
      ModuleSpecs::Autoload.autoload :Concur, fixture(__FILE__, "autoload_concur.rb")

      start = false

      ScratchPad.record []

      t1_val = nil
      t2_val = nil

      fin = false

      t1 = Thread.new do
        Thread.pass until start
        t1_val = ModuleSpecs::Autoload::Concur
        ScratchPad.recorded << :t1_post
        fin = true
      end

      t2_exc = nil

      t2 = Thread.new do
        Thread.pass until t1 and t1[:in_autoload_rb]
        begin
          t2_val = ModuleSpecs::Autoload::Concur
        rescue Exception => e
          t2_exc = e
        else
          Thread.pass until fin
          ScratchPad.recorded << :t2_post
        end
      end

      start = true

      t1.join
      t2.join

      ScratchPad.recorded.should == [:con_pre, :con_post, :t1_post, :t2_post]

      t1_val.should == 1
      t2_val.should == t1_val

      t2_exc.should be_nil

      ModuleSpecs::Autoload.send(:remove_const, :Concur)
    end

    # https://bugs.ruby-lang.org/issues/10892
    it "blocks others threads while doing an autoload" do
      file_path     = fixture(__FILE__, "repeated_concurrent_autoload.rb")
      autoload_path = file_path.sub(/\.rb\Z/, '')
      mod_count     = 30
      thread_count  = 16

      mod_names = []
      mod_count.times do |i|
        mod_name = :"Mod#{i}"
        Object.autoload mod_name, autoload_path
        mod_names << mod_name
      end

      barrier = ModuleSpecs::CyclicBarrier.new thread_count
      ScratchPad.record ModuleSpecs::ThreadSafeCounter.new

      threads = (1..thread_count).map do
        Thread.new do
          mod_names.each do |mod_name|
            break false unless barrier.enabled?

            was_last_one_in = barrier.await # wait for all threads to finish the iteration
            # clean up so we can autoload the same file again
            $LOADED_FEATURES.delete(file_path) if was_last_one_in && $LOADED_FEATURES.include?(file_path)
            barrier.await # get ready for race

            begin
              Object.const_get(mod_name).foo
            rescue NoMethodError
              barrier.disable!
              break false
            end
          end
        end
      end

      # check that no thread got a NoMethodError because of partially loaded module
      threads.all? {|t| t.value}.should be_true

      # check that the autoloaded file was evaled exactly once
      ScratchPad.recorded.get.should == mod_count

      mod_names.each do |mod_name|
        Object.send(:remove_const, mod_name)
      end
    end

    it "raises a NameError in each thread if the constant is not set" do
      file = fixture(__FILE__, "autoload_never_set.rb")
      start = false

      threads = Array.new(10) do
        Thread.new do
          Thread.pass until start
          begin
            ModuleSpecs::Autoload.autoload :NeverSetConstant, file
            Thread.pass
            ModuleSpecs::Autoload::NeverSetConstant
          rescue NameError => e
            e
          ensure
            Thread.pass
          end
        end
      end

      start = true
      threads.each { |t|
        t.value.should be_an_instance_of(NameError)
      }
    end

    it "raises a LoadError in each thread if the file does not exist" do
      file = fixture(__FILE__, "autoload_does_not_exist.rb")
      start = false

      threads = Array.new(10) do
        Thread.new do
          Thread.pass until start
          begin
            ModuleSpecs::Autoload.autoload :FileDoesNotExist, file
            Thread.pass
            ModuleSpecs::Autoload::FileDoesNotExist
          rescue LoadError => e
            e
          ensure
            Thread.pass
          end
        end
      end

      start = true
      threads.each { |t|
        t.value.should be_an_instance_of(LoadError)
      }
    end
  end

  it "loads the registered constant even if the constant was already loaded by another thread" do
    Thread.new {
      ModuleSpecs::Autoload::FromThread::D.foo
    }.value.should == :foo
  end
end
