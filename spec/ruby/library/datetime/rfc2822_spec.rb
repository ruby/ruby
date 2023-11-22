require_relative '../../spec_helper'
require 'date'

describe "DateTime.rfc2822" do
  it "needs to be reviewed for spec completeness"

  it "raises DateError if passed nil" do
    -> { DateTime.rfc2822(nil) }.should raise_error(Date::Error, "invalid date")
  end
end
