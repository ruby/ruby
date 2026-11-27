require_relative '../../../spec_helper'
require 'digest'

describe "Digest::Instance#<<" do
  it "raises a RuntimeError if called" do
    c = Class.new do
      include Digest::Instance
    end
    -> { c.new << "test" }.should.raise(RuntimeError)
  end
end
