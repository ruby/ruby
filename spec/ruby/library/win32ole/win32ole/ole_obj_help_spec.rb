require_relative "../../../spec_helper"

platform_is :windows do
  require_relative '../fixtures/classes'

  describe "WIN32OLE#ole_obj_help" do
    before :each do
      @dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
    end

    it "raises ArgumentError if argument is given" do
      -> { @dict.ole_obj_help(1) }.should raise_error ArgumentError
    end

    it "returns an instance of WIN32OLE::Type" do
      @dict.ole_obj_help.kind_of?(WIN32OLE::Type).should be_true
    end
  end
end
