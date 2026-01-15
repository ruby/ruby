require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Method#helpcontext" do
    before :each do
      ole_type = WIN32OLE::Type.new("Microsoft Scripting Runtime", "FileSystemObject")
      @get_file_version = WIN32OLE::Method.new(ole_type, "GetFileVersion")
      ole_type = WIN32OLE::Type.new("Microsoft Scripting Runtime", "File")
      @m_file_name = WIN32OLE::Method.new(ole_type, "name")
    end

    it "raises ArgumentError if argument is given" do
      -> { @get_file_version.helpcontext(1) }.should raise_error ArgumentError
    end

    it "returns expected value for FileSystemObject's 'GetFileVersion' method" do
      @get_file_version.helpcontext.should == 0
    end

    it "returns expected value for Scripting Runtime's 'name' method" do
      @m_file_name.helpcontext.should == 2181996 # value indicated in MRI's test
    end

  end

end
