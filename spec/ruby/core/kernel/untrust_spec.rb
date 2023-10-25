require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrust" do
  ruby_version_is ""..."3.2" do
    it "is a no-op" do
      suppress_warning do
        o = Object.new
        o.untrust
        o.should_not.untrusted?
      end
    end

    it "warns in verbose mode" do
      -> {
        o = Object.new
        o.untrust
      }.should complain(/Object#untrust is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      Object.new.should_not.respond_to?(:untrust)
    end
  end
end
