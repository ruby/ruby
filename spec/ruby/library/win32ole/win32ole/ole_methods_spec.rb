require_relative "../../../spec_helper"
platform_is :windows do
  require_relative '../fixtures/classes'

  describe "WIN32OLE#ole_methods" do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "raises ArgumentError if argument is given" do
      -> { @dict.ole_methods(1) }.should raise_error ArgumentError
    end

    it "returns an array of WIN32OLE::Methods" do
      @dict.ole_methods.all? { |m| m.kind_of? WIN32OLE::Method }.should be_true
    end

    it "contains a 'AddRef' method for Scripting Dictionary" do
      @dict.ole_methods.map { |m| m.name }.include?('AddRef').should be_true
    end
  end
end
