require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module.new" do
  it "creates a new anonymous Module" do
    Module.new.is_a?(Module).should == true
  end

  it "creates a new Module and passes it to the provided block" do
    test_mod = nil
    m = Module.new do |mod|
      mod.should_not == nil
      self.should == mod
      test_mod = mod
      mod.is_a?(Module).should == true
      Object.new # trying to return something
    end
    test_mod.should == m
  end

  it "evaluates a passed block in the context of the module" do
    fred = Module.new do
      def hello() "hello" end
      def bye()   "bye"   end
    end

    (o = mock('x')).extend(fred)
    o.hello.should == "hello"
    o.bye.should == "bye"
  end

  ruby_version_is "3.3" do
    it "can provide an explicit name" do
      mod = Module.new("fake")
      mod.name.should == "fake"
    end

    it "can override explicit name" do
      mod = Module.new("fake")
      ::Fake = mod
      mod.name.should == "Fake"
    ensure
      ::Object.__send__(:remove_const, "Fake")
    end
  end
end
