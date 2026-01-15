platform_is :windows do
  require 'win32ole'

  describe :win32ole_type_name, shared: true do
    before :each do
      @ole_type = WIN32OLE::Type.new("Microsoft Shell Controls And Automation", "ShellSpecialFolderConstants")
    end

    it "raises ArgumentError if argument is given" do
      -> { @ole_type.send(@method, 1) }.should raise_error ArgumentError
    end

    it "returns a String" do
      @ole_type.send(@method).should == 'ShellSpecialFolderConstants'
    end

  end

end
