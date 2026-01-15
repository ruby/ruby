require_relative '../../spec_helper'
require 'stringio'

# This method is added by io/console on require.
describe "StringIO#getpass" do
  require 'io/console'

  it "is defined by io/console" do
    StringIO.new("example").should.respond_to?(:getpass)
  end
end
