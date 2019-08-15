require_relative '../../spec_helper'
require_relative 'shared/terminate'
require 'strscan'

describe "StringScanner#clear" do
  it_behaves_like :strscan_terminate, :clear

  it "warns in verbose mode that the method is obsolete" do
    s = StringScanner.new("abc")
    -> {
      s.clear
    }.should complain(/clear.*obsolete.*terminate/, verbose: true)

    -> {
      s.clear
    }.should_not complain(verbose: false)
  end
end
