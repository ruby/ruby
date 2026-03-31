require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#terminate" do
  it "set the scan pointer to the end of the string and clear matching data." do
    s = StringScanner.new('This is a test')
    s.terminate
    s.should_not.bol?
    s.should.eos?
  end
end
