require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untaint" do
  ruby_version_is ''...'2.7' do
    it "returns self" do
      o = Object.new
      o.untaint.should equal(o)
    end

    it "clears the tainted bit" do
      o = Object.new.taint
      o.untaint
      o.should_not.tainted?
    end

    it "raises FrozenError on a tainted, frozen object" do
      o = Object.new.taint.freeze
      -> { o.untaint }.should raise_error(FrozenError)
    end

    it "does not raise an error on an untainted, frozen object" do
      o = Object.new.freeze
      o.untaint.should equal(o)
    end
  end
end
