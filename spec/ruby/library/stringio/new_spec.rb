require_relative '../../spec_helper'
require 'stringio'

describe "StringIO.new" do
  it "warns when called with a block" do
    -> { eval("StringIO.new {}") }.should complain(/StringIO::new\(\) does not take block; use StringIO::open\(\) instead/)
  end
end