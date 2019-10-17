require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct-based class#dup" do

  # From https://github.com/jruby/jruby/issues/3686
  it "retains an included module in the ancestor chain for the struct's singleton class" do
    klass = Struct.new(:foo)
    mod = Module.new do
      def hello
        "hello"
      end
    end

    klass.extend(mod)
    klass_dup = klass.dup
    klass_dup.hello.should == "hello"
  end

end
