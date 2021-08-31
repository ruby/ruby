require_relative '../../spec_helper'

describe "Exception" do
  it "has the right class hierarchy" do
    hierarchy = {
      Exception => {
        NoMemoryError => nil,
        ScriptError => {
          LoadError => nil,
          NotImplementedError => nil,
          SyntaxError => nil,
        },
        SecurityError => nil,
        SignalException => {
          Interrupt => nil,
        },
        StandardError => {
          ArgumentError => {
            UncaughtThrowError => nil,
          },
          EncodingError => nil,
          FiberError => nil,
          IOError => {
            EOFError => nil,
          },
          IndexError => {
            KeyError => nil,
            StopIteration => {
              ClosedQueueError => nil,
            },
          },
          LocalJumpError => nil,
          NameError => {
            NoMethodError => nil,
          },
          RangeError => {
            FloatDomainError => nil,
          },
          RegexpError => nil,
          RuntimeError => {
            FrozenError => nil,
          },
          SystemCallError => nil,
          ThreadError => nil,
          TypeError => nil,
          ZeroDivisionError => nil,
        },
        SystemExit => nil,
        SystemStackError => nil,
      },
    }

    traverse = -> parent_class, parent_subclass_hash {
      parent_subclass_hash.each do |child_class, child_subclass_hash|
        child_class.class.should == Class
        child_class.superclass.should == parent_class
        traverse.call(child_class, child_subclass_hash) if child_subclass_hash
      end
    }
    traverse.call(Object, hierarchy)
  end
end
