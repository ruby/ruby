require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrusted?" do
  ruby_version_is ""..."3.2" do
    it "is a no-op" do
      suppress_warning do
        o = mock('o')
        o.should_not.untrusted?
        o.untrust
        o.should_not.untrusted?
      end
    end

    it "warns in verbose mode" do
      -> {
        o = mock('o')
        o.untrusted?
      }.should complain(/Object#untrusted\? is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      Object.new.should_not.respond_to?(:untrusted?)
    end
  end
end
