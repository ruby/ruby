require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrust" do
  ruby_version_is ''...'2.7' do
    it "returns self" do
      o = Object.new
      o.untrust.should equal(o)
    end

    it "sets the untrusted bit" do
      o = Object.new
      o.untrust
      o.should.untrusted?
    end

    it "raises FrozenError on a trusted, frozen object" do
      o = Object.new.freeze
      -> { o.untrust }.should raise_error(FrozenError)
    end

    it "does not raise an error on an untrusted, frozen object" do
      o = Object.new.untrust.freeze
      o.untrust.should equal(o)
    end
  end
end
