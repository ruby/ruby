require_relative '../../spec_helper'
require_relative 'shared/peek'
require 'strscan'

describe "StringScanner#peep" do
  it_behaves_like :strscan_peek, :peep

  it "warns in verbose mode that the method is obsolete" do
    s = StringScanner.new("abc")
    lambda {
      $VERBOSE = true
      s.peep(1)
    }.should complain(/peep.*obsolete.*peek/)

    lambda {
      $VERBOSE = false
      s.peep(1)
    }.should_not complain
  end
end
