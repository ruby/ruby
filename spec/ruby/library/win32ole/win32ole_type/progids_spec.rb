require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Type.progids" do
    it "raises ArgumentError if an argument is given" do
      -> { WIN32OLE::Type.progids(1) }.should raise_error ArgumentError
    end

    it "returns an array containing 'Shell.Explorer'" do
      WIN32OLE::Type.progids().include?('Shell.Explorer').should be_true
    end

  end
end
