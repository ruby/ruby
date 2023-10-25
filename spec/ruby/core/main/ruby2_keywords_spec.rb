require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "main.ruby2_keywords" do
  it "is the same as Object.ruby2_keywords" do
    main = TOPLEVEL_BINDING.receiver
    main.should have_private_method(:ruby2_keywords)
  end
end
