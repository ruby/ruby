require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#fixed_anchor?" do
  it "returns whether the fixed-anchor property is set" do
    s = StringScanner.new("foo", fixed_anchor: true)
    s.should.fixed_anchor?

    s = StringScanner.new("foo", fixed_anchor: false)
    s.should_not.fixed_anchor?
  end

  it "is set to false by default" do
    s = StringScanner.new("foo")
    s.should_not.fixed_anchor?
  end
end
