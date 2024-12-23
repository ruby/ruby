require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require 'win32ole'

  describe "WIN32OLE_TYPE.progids" do
    it "raises ArgumentError if an argument is given" do
      -> { WIN32OLE_TYPE.progids(1) }.should raise_error ArgumentError
    end

    it "returns an array containing 'Shell.Explorer'" do
      WIN32OLE_TYPE.progids().include?('Shell.Explorer').should be_true
    end

  end
ensure
  $VERBOSE = verbose
end
