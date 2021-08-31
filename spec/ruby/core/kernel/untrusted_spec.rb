require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#untrusted?" do
  ruby_version_is ''...'2.7' do
    it "returns the untrusted status of an object" do
      o = mock('o')
      o.should_not.untrusted?
      o.untrust
      o.should.untrusted?
    end

    it "has no effect on immediate values" do
      a = nil
      b = true
      c = false
      a.untrust
      b.untrust
      c.untrust
      a.should_not.untrusted?
      b.should_not.untrusted?
      c.should_not.untrusted?
    end

    it "has effect on immediate values" do
      d = 1
      -> { d.untrust }.should_not raise_error(RuntimeError)
    end
  end

  ruby_version_is "2.7"..."3.0" do
    it "is a no-op" do
      o = mock('o')
      o.should_not.untrusted?
      o.untrust
      o.should_not.untrusted?
    end

    it "warns in verbose mode" do
      -> {
        o = mock('o')
        o.untrusted?
      }.should complain(/Object#untrusted\? is deprecated and will be removed in Ruby 3.2/, verbose: true)
    end
  end
end
