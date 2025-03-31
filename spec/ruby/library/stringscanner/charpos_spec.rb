require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#charpos" do
  it "returns character index corresponding to the current position" do
    s = StringScanner.new("abc")

    s.scan_until(/b/)
    s.charpos.should == 2
  end

  it "is multi-byte character sensitive" do
    s = StringScanner.new("abcädeföghi")

    s.scan_until(/ö/)
    s.charpos.should == 8
  end
end
