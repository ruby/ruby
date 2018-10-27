platform_is :windows do
  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    describe "WIN32OLE#invoke" do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "get name by invoking 'validateOnParse' OLE method" do
        @xml_dom.invoke('validateOnParse').should be_true
      end
    end
  end
end
