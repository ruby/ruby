require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#taint" do
  ruby_version_is ""..."3.2" do
    it "is a no-op" do
      suppress_warning do
        o = Object.new
        o.taint
        o.should_not.tainted?
      end
    end

    it "warns in verbose mode" do
      -> {
        obj = mock("tainted")
        obj.taint
      }.should complain(/Object#taint is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      Object.new.should_not.respond_to?(:taint)
    end
  end
end
