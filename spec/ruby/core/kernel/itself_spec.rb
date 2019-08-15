require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#itself" do
  it "returns the receiver itself" do
    foo = Object.new
    foo.itself.should equal foo
  end
end
