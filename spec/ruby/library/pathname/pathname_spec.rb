require_relative '../../spec_helper'
require 'pathname'

describe "Kernel#Pathname" do
  it "is a private instance method" do
    Kernel.should have_private_instance_method(:Pathname)
  end

  it "is also a public method" do
    Kernel.should have_method(:Pathname)
  end

  it "returns same argument when called with a pathname argument" do
    path = Pathname('foo')
    new_path = Pathname(path)

    path.should.equal?(new_path)
  end
end
