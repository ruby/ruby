require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#taint" do
  ruby_version_is ""..."3.0" do
    it "is a no-op" do
      o = Object.new
      o.taint
      o.should_not.tainted?
    end

    it "warns in verbose mode" do
      -> {
        obj = mock("tainted")
        obj.taint
      }.should complain(/Object#taint is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
