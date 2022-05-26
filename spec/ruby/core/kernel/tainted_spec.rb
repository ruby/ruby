require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#tainted?" do
  ruby_version_is ""..."3.0" do
    it "is a no-op" do
      o = mock('o')
      p = mock('p')
      p.taint
      o.should_not.tainted?
      p.should_not.tainted?
    end

    it "warns in verbose mode" do
      -> {
        o = mock('o')
        o.tainted?
      }.should complain(/Object#tainted\? is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
