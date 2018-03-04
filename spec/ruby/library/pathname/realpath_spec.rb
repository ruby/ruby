require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#realpath" do

  it "returns a Pathname" do
    Pathname.pwd.realpath.should be_an_instance_of(Pathname)
  end

end
