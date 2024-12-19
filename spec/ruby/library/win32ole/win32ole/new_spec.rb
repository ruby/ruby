require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'

  describe "WIN32OLESpecs.new_ole" do
    it "creates a WIN32OLE object from OLE server name" do
      shell = WIN32OLESpecs.new_ole 'Shell.Application'
      shell.should be_kind_of WIN32OLE
    end

    it "creates a WIN32OLE object from valid CLSID" do
      shell = WIN32OLESpecs.new_ole("{13709620-C279-11CE-A49E-444553540000}")
      shell.should be_kind_of WIN32OLE
    end

    it "raises TypeError if argument cannot be converted to String" do
      -> { WIN32OLESpecs.new_ole(42) }.should raise_error( TypeError )
    end

    it "raises WIN32OLERuntimeError if invalid string is given" do
      -> { WIN32OLE.new('foo') }.should raise_error( WIN32OLERuntimeError )
    end

  end

ensure
  $VERBOSE = verbose
end
