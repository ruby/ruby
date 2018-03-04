require_relative '../../spec_helper'
require_relative 'shared/get_byte'
require_relative 'shared/extract_range'
require 'strscan'

describe "StringScanner#getbyte" do
  it_behaves_like :strscan_get_byte, :getbyte

  it "warns in verbose mode that the method is obsolete" do
    s = StringScanner.new("abc")
    lambda {
      $VERBOSE = true
      s.getbyte
    }.should complain(/getbyte.*obsolete.*get_byte/)

    lambda {
      $VERBOSE = false
      s.getbyte
    }.should_not complain
  end

  it_behaves_like :extract_range, :getbyte
end
