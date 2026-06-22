require_relative "../../../spec_helper"
platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE::Type.new" do
    it "raises ArgumentError with no argument" do
      -> { WIN32OLE::Type.new }.should.raise ArgumentError
    end

    it "raises ArgumentError with invalid string" do
      -> { WIN32OLE::Type.new("foo") }.should.raise ArgumentError
    end

    it "raises TypeError if second argument is not a String" do
      -> { WIN32OLE::Type.new(1,2) }.should.raise TypeError
      -> {
        WIN32OLE::Type.new('Microsoft Shell Controls And Automation',2)
      }.should.raise TypeError
    end

    it "raise WIN32OLE::RuntimeError if OLE object specified is not found" do
      -> {
        WIN32OLE::Type.new('Microsoft Shell Controls And Automation','foo')
      }.should.raise WIN32OLE::RuntimeError
      -> {
        WIN32OLE::Type.new('Microsoft Shell Controls And Automation','Application')
      }.should.raise WIN32OLE::RuntimeError
    end

    it "creates WIN32OLE::Type object from name and valid type" do
      ole_type = WIN32OLE::Type.new("Microsoft Shell Controls And Automation", "Shell")
      ole_type.should.is_a? WIN32OLE::Type
    end

    it "creates WIN32OLE::Type object from CLSID and valid type" do
      ole_type2 = WIN32OLE::Type.new("{13709620-C279-11CE-A49E-444553540000}", "Shell")
      ole_type2.should.is_a? WIN32OLE::Type
    end

  end
end
