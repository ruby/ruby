require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Method#params" do
    before :each do
      ole_type = WIN32OLE::Type.new("Microsoft Scripting Runtime", "File")
      @m_file_name = WIN32OLE::Method.new(ole_type, "name")
      ole_type = WIN32OLE::Type.new("Microsoft Shell Controls And Automation", "Shell")
      @m_browse_for_folder = WIN32OLE::Method.new(ole_type, "BrowseForFolder")
    end

    it "raises ArgumentError if argument is given" do
      -> { @m_file_name.params(1) }.should raise_error ArgumentError
    end

    it "returns empty array for Scripting Runtime's 'name' method" do
      @m_file_name.params.should be_kind_of Array
      @m_file_name.params.should be_empty
    end

    it "returns 4-element array of WIN32OLE::Param for Shell's 'BrowseForFolder' method" do
      @m_browse_for_folder.params.all? { |p| p.kind_of? WIN32OLE::Param }.should be_true
      @m_browse_for_folder.params.size == 4
    end

  end

end
