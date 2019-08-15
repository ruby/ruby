require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner.must_C_version" do
  it "returns self" do
     StringScanner.must_C_version.should == StringScanner
  end
end
