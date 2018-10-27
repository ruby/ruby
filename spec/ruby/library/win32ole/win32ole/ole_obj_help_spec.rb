platform_is :windows do
  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    describe "WIN32OLE#ole_obj_help" do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "raises ArgumentError if argument is given" do
        lambda { @xml_dom.ole_obj_help(1) }.should raise_error ArgumentError
      end

      it "returns an instance of WIN32OLE_TYPE" do
        @xml_dom.ole_obj_help.kind_of?(WIN32OLE_TYPE).should be_true
      end
    end
  end
end
