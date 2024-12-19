require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'

  describe "WIN32OLE.create_guid" do
    it "generates guid with valid format" do
      WIN32OLE.create_guid.should =~ /^\{[A-Z0-9]{8}\-[A-Z0-9]{4}\-[A-Z0-9]{4}\-[A-Z0-9]{4}\-[A-Z0-9]{12}/
    end
  end
ensure
  $VERBOSE = verbose
end
