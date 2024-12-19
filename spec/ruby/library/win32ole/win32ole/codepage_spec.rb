require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'

  describe "WIN32OLE.codepage=" do
    it "sets codepage" do
      cp = WIN32OLE.codepage
      WIN32OLE.codepage = WIN32OLE::CP_UTF8
      WIN32OLE.codepage.should == WIN32OLE::CP_UTF8
      WIN32OLE.codepage = cp
    end
  end

ensure
  $VERBOSE = verbose
end
