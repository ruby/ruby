require_relative '../../../spec_helper'
require 'fiddle'

describe "Fiddle::Handle#initialize" do
  it "raises Fiddle::DLError if the library cannot be found" do
    -> {
      Fiddle::Handle.new("doesnotexist.doesnotexist")
    }.should raise_error(Fiddle::DLError)
  end
end
