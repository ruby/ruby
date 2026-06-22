require_relative "../../../spec_helper"
platform_is :windows do
  require_relative '../fixtures/classes'

  describe "WIN32OLE.connect" do
    it "creates WIN32OLE object given valid argument" do
      obj = WIN32OLE.connect("winmgmts:")
      obj.should.is_a? WIN32OLE
    end

    it "raises TypeError when given invalid argument" do
      -> { WIN32OLE.connect 1 }.should.raise TypeError
    end

  end
end
