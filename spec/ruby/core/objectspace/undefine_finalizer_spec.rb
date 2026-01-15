require_relative '../../spec_helper'

describe "ObjectSpace.undefine_finalizer" do
  it "removes finalizers for an object" do
    code = <<~RUBY
      obj = Object.new
      ObjectSpace.define_finalizer(obj, proc { |id| puts "hello" })
      ObjectSpace.undefine_finalizer(obj)
    RUBY

    ruby_exe(code).should.empty?
  end

  it "should not remove finalizers for a frozen object" do
    code = <<~RUBY
      obj = Object.new
      ObjectSpace.define_finalizer(obj, proc { |id| print "ok" })
      obj.freeze
      begin
        ObjectSpace.undefine_finalizer(obj)
      rescue
      end
    RUBY

    ruby_exe(code).should == "ok"
  end

  it "should raise when removing finalizers for a frozen object" do
    obj = Object.new
    obj.freeze
    -> { ObjectSpace.undefine_finalizer(obj) }.should raise_error(FrozenError)
  end
end
