require_relative '../../spec_helper'
require 'pathname'

describe "Kernel#Pathname" do
  it "is a private instance method" do
    Kernel.private_instance_methods(false).should.include?(:Pathname)
  end

  it "is also a public method" do
    Kernel.should.respond_to?(:Pathname)
  end

  it "returns same argument when called with a pathname argument" do
    path = Pathname('foo')
    new_path = Pathname(path)

    path.should.equal?(new_path)
  end
end
