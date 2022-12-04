require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#print" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:print)
  end

  it "delegates to $stdout" do
    -> { print :arg }.should output("arg")
  end

  it "prints $_ when no arguments are given" do
    orig_value = $_
    $_ = 'foo'
    -> { print }.should output("foo")
  ensure
    $_ = orig_value
  end
end

describe "Kernel.print" do
  it "needs to be reviewed for spec completeness"
end
