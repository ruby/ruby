require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#trust" do
  it "has been removed" do
    Object.new.should_not.respond_to?(:trust)
  end
end
