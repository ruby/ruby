require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#realdirpath" do

  it "returns a Pathname" do
    Pathname.pwd.realdirpath.should be_an_instance_of(Pathname)
  end

end
