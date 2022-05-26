require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untaint" do
  ruby_version_is ""..."3.0" do
    it "is a no-op" do
      o = Object.new.taint
      o.should_not.tainted?
      o.untaint
      o.should_not.tainted?
    end

    it "warns in verbose mode" do
      -> {
        o = Object.new.taint
        o.untaint
      }.should complain(/Object#untaint is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
