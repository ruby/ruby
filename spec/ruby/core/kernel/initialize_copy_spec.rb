require_relative '../../spec_helper'

describe "Kernel#initialize_copy" do
  it "returns self" do
    obj = Object.new
    obj.send(:initialize_copy, obj).should.equal?(obj)
  end

  it "does nothing if the argument is the same as the receiver" do
    obj = Object.new
    obj.send(:initialize_copy, obj).should.equal?(obj)

    obj = Object.new.freeze
    obj.send(:initialize_copy, obj).should.equal?(obj)

    1.send(:initialize_copy, 1).should.equal?(1)
  end

  it "raises FrozenError if the receiver is frozen" do
    -> { Object.new.freeze.send(:initialize_copy, Object.new) }.should raise_error(FrozenError)
    -> { 1.send(:initialize_copy, Object.new) }.should raise_error(FrozenError)
  end

  it "raises TypeError if the objects are of different class" do
    klass = Class.new
    sub = Class.new(klass)
    a = klass.new
    b = sub.new
    message = 'initialize_copy should take same class object'
    -> { a.send(:initialize_copy, b) }.should raise_error(TypeError, message)
    -> { b.send(:initialize_copy, a) }.should raise_error(TypeError, message)

    -> { a.send(:initialize_copy, 1) }.should raise_error(TypeError, message)
    -> { a.send(:initialize_copy, 1.0) }.should raise_error(TypeError, message)
  end
end
