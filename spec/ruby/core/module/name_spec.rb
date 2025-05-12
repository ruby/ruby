require_relative '../../spec_helper'
require_relative 'fixtures/module'

describe "Module#name" do
  it "is nil for an anonymous module" do
    Module.new.name.should be_nil
  end

  it "is not nil when assigned to a constant in an anonymous module" do
    m = Module.new
    m::N = Module.new
    m::N.name.should.end_with? '::N'
  end

  it "is not nil for a nested module created with the module keyword" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x[0-9a-f]+>::N\z/
  end

  it "returns nil for a singleton class" do
    Module.new.singleton_class.name.should be_nil
    String.singleton_class.name.should be_nil
    Object.new.singleton_class.name.should be_nil
  end

  it "changes when the module is reachable through a constant path" do
    m = Module.new
    module m::N; end
    m::N.name.should =~ /\A#<Module:0x\h+>::N\z/
    ModuleSpecs::Anonymous::WasAnnon = m::N
    m::N.name.should == "ModuleSpecs::Anonymous::WasAnnon"
  ensure
    ModuleSpecs::Anonymous.send(:remove_const, :WasAnnon)
  end

  it "may be the repeated in different module objects" do
    m = Module.new
    n = Module.new

    suppress_warning do
      ModuleSpecs::Anonymous::SameName = m
      ModuleSpecs::Anonymous::SameName = n
    end

    m.name.should == "ModuleSpecs::Anonymous::SameName"
    n.name.should == "ModuleSpecs::Anonymous::SameName"
  end

  it "is set after it is removed from a constant" do
    module ModuleSpecs
      module ModuleToRemove
      end

      mod = ModuleToRemove
      remove_const(:ModuleToRemove)
      mod.name.should == "ModuleSpecs::ModuleToRemove"
    end
  end

  it "is set after it is removed from a constant under an anonymous module" do
    m = Module.new
    module m::Child; end
    child = m::Child
    m.send(:remove_const, :Child)
    child.name.should =~ /\A#<Module:0x\h+>::Child\z/
  end

  it "is set when opened with the module keyword" do
    ModuleSpecs.name.should == "ModuleSpecs"
  end

  it "is set when a nested module is opened with the module keyword" do
    ModuleSpecs::Anonymous.name.should == "ModuleSpecs::Anonymous"
  end

  it "is set when assigning to a constant (constant path matches outer module name)" do
    m = Module.new
    ModuleSpecs::Anonymous::A = m
    m.name.should == "ModuleSpecs::Anonymous::A"
  ensure
    ModuleSpecs::Anonymous.send(:remove_const, :A)
  end

  it "is set when assigning to a constant (constant path does not match outer module name)" do
    m = Module.new
    ModuleSpecs::Anonymous::SameChild::A = m
    m.name.should == "ModuleSpecs::Anonymous::Child::A"
  ensure
    ModuleSpecs::Anonymous::SameChild.send(:remove_const, :A)
  end

  it "is not modified when assigning to a new constant after it has been accessed" do
    m = Module.new
    ModuleSpecs::Anonymous::B = m
    m.name.should == "ModuleSpecs::Anonymous::B"
    ModuleSpecs::Anonymous::C = m
    m.name.should == "ModuleSpecs::Anonymous::B"
  ensure
    ModuleSpecs::Anonymous.send(:remove_const, :B)
    ModuleSpecs::Anonymous.send(:remove_const, :C)
  end

  it "is not modified when assigned to a different anonymous module" do
    m = Module.new
    module m::M; end
    first_name = m::M.name.dup
    module m::N; end
    m::N::F = m::M
    m::M.name.should == first_name
  end

  # http://bugs.ruby-lang.org/issues/6067
  it "is set with a conditional assignment to a nested constant" do
    eval("ModuleSpecs::Anonymous::F ||= Module.new")
    ModuleSpecs::Anonymous::F.name.should == "ModuleSpecs::Anonymous::F"
  end

  it "is set with a conditional assignment to a constant" do
    module ModuleSpecs::Anonymous
      D ||= Module.new
    end
    ModuleSpecs::Anonymous::D.name.should == "ModuleSpecs::Anonymous::D"
  end

  # http://redmine.ruby-lang.org/issues/show/1833
  it "preserves the encoding in which the class was defined" do
    require fixture(__FILE__, "name")
    ModuleSpecs::NameEncoding.new.name.encoding.should == Encoding::UTF_8
  end

  it "is set when the anonymous outer module name is set (module in one single constant)" do
    m = Module.new
    m::N = Module.new
    ModuleSpecs::Anonymous::E = m
    m::N.name.should == "ModuleSpecs::Anonymous::E::N"
  ensure
    ModuleSpecs::Anonymous.send(:remove_const, :E)
  end

  # https://bugs.ruby-lang.org/issues/19681
  it "is set when the anonymous outer module name is set (module in several constants)" do
    m = Module.new
    m::N = Module.new
    m::O = m::N
    ModuleSpecs::Anonymous::StoredInMultiplePlaces = m
    valid_names = [
      "ModuleSpecs::Anonymous::StoredInMultiplePlaces::N",
      "ModuleSpecs::Anonymous::StoredInMultiplePlaces::O"
    ]
    valid_names.should include(m::N.name) # You get one of the two, but you don't know which one.
  ensure
    ModuleSpecs::Anonymous.send(:remove_const, :StoredInMultiplePlaces)
  end

  it "is set in #const_added callback when a module defined in the top-level scope" do
    ruby_exe(<<~RUBY, args: "2>&1").chomp.should == "TEST1\nTEST2"
      class Module
        def const_added(name)
          puts const_get(name).name
        end
      end

      # module with name
      module TEST1
      end

      # anonymous module
      TEST2 = Module.new
    RUBY
  end

  it "is set in #const_added callback for a nested module when an outer module defined in the top-level scope" do
    ScratchPad.record []

    ModuleSpecs::NameSpecs::NamedModule = Module.new do
      def self.const_added(name)
        ScratchPad << const_get(name).name
      end

      module self::A
        def self.const_added(name)
          ScratchPad << const_get(name).name
        end

        module self::B
        end
      end
    end

    ScratchPad.recorded.should.one?(/#<Module.+>::A$/)
    ScratchPad.recorded.should.one?(/#<Module.+>::A::B$/)
  end

  it "returns a frozen String" do
    ModuleSpecs.name.should.frozen?
  end

  it "always returns the same String for a given Module" do
    s1 = ModuleSpecs.name
    s2 = ModuleSpecs.name
    s1.should equal(s2)
  end
end
