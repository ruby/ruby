require_relative '../../spec_helper'
require 'stringio'

describe "StringIO.new" do
  it "does not use the given block and warns to use StringIO::open" do
    -> {
      StringIO.new { raise }
    }.should complain(/warning: StringIO::new\(\) does not take block; use StringIO::open\(\) instead/)
  end
end
