require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Method#visible?" do
    before :each do
      ole_type = WIN32OLE::Type.new("Microsoft Shell Controls And Automation", "Shell")
      @m_browse_for_folder = WIN32OLE::Method.new(ole_type, "BrowseForFolder")
    end

    it "raises ArgumentError if argument is given" do
      -> { @m_browse_for_folder.visible?(1) }.should raise_error ArgumentError
    end

    it "returns true for Shell Control's 'BrowseForFolder' method" do
      @m_browse_for_folder.visible?.should be_true
    end

  end

end
