require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untaint" do
  ruby_version_is ""..."3.2" do
    it "is a no-op" do
      suppress_warning do
        o = Object.new.taint
        o.should_not.tainted?
        o.untaint
        o.should_not.tainted?
      end
    end

    it "warns in verbose mode" do
      -> {
        o = Object.new.taint
        o.untaint
      }.should complain(/Object#untaint is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      Object.new.should_not.respond_to?(:untaint)
    end
  end
end
