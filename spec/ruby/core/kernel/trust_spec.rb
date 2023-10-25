require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#trust" do
  ruby_version_is ""..."3.2" do
    it "is a no-op" do
      suppress_warning do
        o = Object.new.untrust
        o.should_not.untrusted?
        o.trust
        o.should_not.untrusted?
      end
    end

    it "warns in verbose mode" do
      -> {
        o = Object.new.untrust
        o.trust
      }.should complain(/Object#trust is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      Object.new.should_not.respond_to?(:trust)
    end
  end
end
