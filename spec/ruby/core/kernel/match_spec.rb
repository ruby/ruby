require_relative '../../spec_helper'

describe "Kernel#=~" do
  it "is no longer defined" do
    Object.new.should_not.respond_to?(:=~)
  end
end
