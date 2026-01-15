require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Type.typelibs for Shell Controls" do
    before :each do
      @ole_type = WIN32OLE::Type.new("Microsoft Shell Controls And Automation", "Shell")
    end

    after :each do
      @ole_type = nil
    end

    it "raises ArgumentError if any argument is give" do
      -> { WIN32OLE::Type.typelibs(1) }.should raise_error ArgumentError
    end

    it "returns array of type libraries" do
      WIN32OLE::Type.typelibs().include?("Microsoft Shell Controls And Automation").should be_true
    end

  end
end
