require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "WeakRef#__getobj__" do
  it "returns the object if it is reachable" do
    obj = Object.new
    ref = WeakRef.new(obj)
    ref.__getobj__.should equal(obj)
  end

  it "raises WeakRef::RefError if the object is no longer reachable" do
    ref = WeakRefSpec.make_dead_weakref
    -> {
      ref.__getobj__
    }.should raise_error(WeakRef::RefError)
  end
end
