require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#trust" do
  ruby_version_is ''...'2.7' do
    it "returns self" do
      o = Object.new
      o.trust.should equal(o)
    end

    it "clears the untrusted bit" do
      o = Object.new.untrust
      o.trust
      o.should_not.untrusted?
    end

    it "raises FrozenError on an untrusted, frozen object" do
      o = Object.new.untrust.freeze
      -> { o.trust }.should raise_error(FrozenError)
    end

    it "does not raise an error on a trusted, frozen object" do
      o = Object.new.freeze
      o.trust.should equal(o)
    end
  end

  ruby_version_is "2.7"..."3.0" do
    it "is a no-op" do
      o = Object.new.untrust
      o.should_not.untrusted?
      o.trust
      o.should_not.untrusted?
    end

    it "warns in verbose mode" do
      -> {
        o = Object.new.untrust
        o.trust
      }.should complain(/Object#trust is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
