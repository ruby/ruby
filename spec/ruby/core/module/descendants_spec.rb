require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "4.1" do
  describe "Module#descendants" do
    it "returns a list of classes inheriting from self" do
      parent = Class.new
      child = Class.new(parent)
      grandchild = Class.new(child)

      assert_descendants(parent, [child, grandchild])
      assert_descendants(child, [grandchild])
      assert_descendants(grandchild, [])
    end

    it "returns a list of modules and classes including self" do
      mod = Module.new
      including_mod = Module.new { include mod }
      klass = Class.new { include including_mod }
      subclass = Class.new(klass)

      assert_descendants(mod, [including_mod, klass, subclass])
      assert_descendants(including_mod, [klass, subclass])
    end

    it "returns modules and classes prepending self" do
      mod = Module.new
      prepending_mod = Module.new { prepend mod }
      klass = Class.new { prepend mod }

      assert_descendants(mod, [prepending_mod, klass])
    end

    it "returns modules and classes including self after prepending another module" do
      prepended = Module.new
      mod = Module.new
      klass = Class.new { prepend prepended; include mod }
      including_mod = Module.new { prepend prepended; include mod }

      assert_descendants(mod, [klass, including_mod])
    end

    it "does not return the internal nodes created by prepend" do
      parent = Class.new { prepend Module.new }
      child = Class.new(parent) { prepend Module.new }

      assert_descendants(parent, [child])
    end

    it "does not return modules and classes including a clone of self" do
      mod = Module.new
      clone = mod.clone
      klass = Class.new { include clone }

      mod.descendants.should_not.include?(klass)
      clone.descendants.should.include?(klass)
    end

    it "returns modules and classes into which self is included later" do
      mod = Module.new
      including_mod = Module.new
      klass = Class.new { include including_mod }
      including_mod.include(mod)

      assert_descendants(mod, [including_mod, klass])
    end

    it "does not return self" do
      mod = Module.new
      Class.new { include mod }

      mod.descendants.should_not.include?(mod)
      ModuleSpecs::Parent.descendants.should_not.include?(ModuleSpecs::Parent)
    end

    it "returns an empty Array if there is no descendant" do
      Module.new.descendants.should == []
      Class.new.descendants.should == []
    end

    it "does not return singleton classes" do
      mod = Module.new
      obj = Object.new
      obj.extend(mod)
      klass = Class.new { extend mod }

      mod.descendants.should_not.include?(obj.singleton_class)
      mod.descendants.should_not.include?(klass.singleton_class)
      ModuleSpecs::Internal.descendants.should_not.include?(ModuleSpecs::Child.singleton_class)
    end

    it "does not return refinements" do
      klass = Class.new
      refinement = nil
      Module.new do
        refinement = refine(klass) do
          def refined_method; end
        end
      end

      klass.descendants.should_not.include?(refinement)
      refinement.descendants.should_not.include?(klass)
    end

    it "has 1 entry per module or class" do
      mod = Module.new
      including_mod = Module.new { include mod }
      Class.new do
        include mod
        include including_mod
      end

      descendants = mod.descendants
      descendants.should == descendants.uniq

      descendants = ModuleSpecs::Parent.descendants
      descendants.should == descendants.uniq
    end

    it "returns the modules and classes whose ancestors include self" do
      mods = [ModuleSpecs::Basic, ModuleSpecs::Super, ModuleSpecs::Parent,
              ModuleSpecs::Child, ModuleSpecs::Child2, ModuleSpecs::Grandchild]

      mods.each do |mod|
        descendants = mod.descendants
        mods.each do |other|
          next if mod.equal?(other)
          descendants.include?(other).should == other.ancestors.include?(mod)
        end
      end
    end

    def assert_descendants(mod, descendants)
      mod.descendants.sort_by(&:object_id).should == descendants.sort_by(&:object_id)
    end
  end
end
