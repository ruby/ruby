require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#const_added" do
  ruby_version_is "3.2" do
    it "is a private instance method" do
      Module.should have_private_instance_method(:const_added)
    end

    it "returns nil in the default implementation" do
      Module.new do
        const_added(:TEST).should == nil
      end
    end

    it "is called when a new constant is assigned on self" do
      ScratchPad.record []

      mod = Module.new do
        def self.const_added(name)
          ScratchPad << name
        end
      end

      mod.module_eval(<<-RUBY, __FILE__, __LINE__ + 1)
        TEST = 1
      RUBY

      ScratchPad.recorded.should == [:TEST]
    end

    it "is called when a new constant is assigned on self through const_set" do
      ScratchPad.record []

      mod = Module.new do
        def self.const_added(name)
          ScratchPad << name
        end
      end

      mod.const_set(:TEST, 1)

      ScratchPad.recorded.should == [:TEST]
    end

    it "is called when a new module is defined under self" do
      ScratchPad.record []

      mod = Module.new do
        def self.const_added(name)
          ScratchPad << name
        end
      end

      mod.module_eval(<<-RUBY, __FILE__, __LINE__ + 1)
        module SubModule
        end

        module SubModule
        end
      RUBY

      ScratchPad.recorded.should == [:SubModule]
    end

    it "is called when a new class is defined under self" do
      ScratchPad.record []

      mod = Module.new do
        def self.const_added(name)
          ScratchPad << name
        end
      end

      mod.module_eval(<<-RUBY, __FILE__, __LINE__ + 1)
        class SubClass
        end

        class SubClass
        end
      RUBY

      ScratchPad.recorded.should == [:SubClass]
    end

    it "is called when an autoload is defined" do
      ScratchPad.record []

      mod = Module.new do
        def self.const_added(name)
          ScratchPad << name
        end
      end

      mod.autoload :Autoload, "foo"
      ScratchPad.recorded.should == [:Autoload]
    end

    it "is called with a precise caller location with the line of definition" do
      ScratchPad.record []

      mod = Module.new do
        def self.const_added(name)
          location = caller_locations(1, 1)[0]
          ScratchPad << location.lineno
        end
      end

      line = __LINE__
      mod.module_eval(<<-RUBY, __FILE__, __LINE__ + 1)
        TEST = 1

        module SubModule
        end

        class SubClass
        end
      RUBY

      mod.const_set(:CONST_SET, 1)

      ScratchPad.recorded.should == [line + 2, line + 4, line + 7, line + 11]
    end
  end
end
