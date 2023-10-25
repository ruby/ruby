require_relative '../../spec_helper'

describe "Regexp#casefold?" do
  it "returns the value of the case-insensitive flag" do
    /abc/i.should.casefold?
    /xyz/.should_not.casefold?
  end
end
