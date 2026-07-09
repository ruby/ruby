require_relative '../../spec_helper'
require 'weakref'

describe "WeakRef#allocate" do
  it "assigns nil as the reference" do
    -> { WeakRef.allocate.__getobj__ }.should.raise(WeakRef::RefError)
  end
end
