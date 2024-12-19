require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'

  describe "WIN32OLE#ole_put_methods" do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "raises ArgumentError if argument is given" do
      -> { @dict.ole_put_methods(1) }.should raise_error ArgumentError
    end

    it "returns an array of WIN32OLE_METHODs" do
      @dict.ole_put_methods.all? { |m| m.kind_of? WIN32OLE_METHOD }.should be_true
    end

    it "contains a 'Key' method for Scripting Dictionary" do
      @dict.ole_put_methods.map { |m| m.name }.include?('Key').should be_true
    end
  end
ensure
  $VERBOSE = verbose
end
