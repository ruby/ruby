require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrust" do
  ruby_version_is ""..."3.0" do
    it "is a no-op" do
      o = Object.new
      o.untrust
      o.should_not.untrusted?
    end

    it "warns in verbose mode" do
      -> {
        o = Object.new
        o.untrust
      }.should complain(/Object#untrust is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
