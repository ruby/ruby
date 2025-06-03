require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Method.new" do
    before :each do
      @ole_type = WIN32OLE::Type.new("Microsoft Shell Controls And Automation", "Shell")
    end

    it "raises TypeError when given non-strings" do
      -> { WIN32OLE::Method.new(1, 2) }.should raise_error TypeError
    end

    it "raises ArgumentError if only 1 argument is given" do
      -> { WIN32OLE::Method.new("hello") }.should raise_error ArgumentError
      -> { WIN32OLE::Method.new(@ole_type) }.should raise_error ArgumentError
    end

    it "returns a valid WIN32OLE::Method object" do
      WIN32OLE::Method.new(@ole_type, "Open").should be_kind_of WIN32OLE::Method
      WIN32OLE::Method.new(@ole_type, "open").should be_kind_of WIN32OLE::Method
    end

    it "raises WIN32OLE::RuntimeError if the method does not exist" do
      -> { WIN32OLE::Method.new(@ole_type, "NonexistentMethod") }.should raise_error WIN32OLE::RuntimeError
    end

    it "raises TypeError if second argument is not a String" do
      -> { WIN32OLE::Method.new(@ole_type, 5) }.should raise_error TypeError
    end

  end

end
