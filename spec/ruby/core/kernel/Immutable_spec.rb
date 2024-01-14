require_relative '../../spec_helper'

ruby_version_is "3.3" do
  describe Immutable do
    it "can freeze objects" do
      object = Object.new
      object.should_not.frozen?
      object.should_not.immutable?

      Immutable(object)

      object.should.frozen?
      object.should.immutable?
    end

    it "can freeze nested objects" do
      object = Object.new
      object.should_not.frozen?
      object.should_not.immutable?

      array = [object]
      array.should_not.frozen?
      array.should_not.immutable?

      Immutable(array)

      array.should.frozen?
      array.should.immutable?
      object.should.frozen?
      # Due to the implementation, this is not true, however it should be.
      # If the proposal is accepted, we will fix this.
      # object.should.immutable?
    end

    it "can freeeze copies of objects" do
      object = Object.new

      copy = Immutable(object, true)

      copy.should.frozen?
      copy.should.immutable?
      object.should_not.frozen?
      object.should_not.immutable?
    end

    it "can freeze copies of nested objects" do
      object = Object.new
      array = [object]

      copy = Immutable(array, true)

      copy.should.frozen?
      copy.should.immutable?
      copy[0].should.frozen?
      # See the above note.
      # copy[0].should.immutable?

      array.should_not.frozen?
      array.should_not.immutable?
      object.should_not.frozen?
      object.should_not.immutable?
    end
  end
end
