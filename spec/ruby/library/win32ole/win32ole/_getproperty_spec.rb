platform_is :windows do
  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    describe "WIN32OLE#_getproperty" do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "gets validateOnParse" do
        @xml_dom._getproperty(65, [], []).should be_true
      end
    end
  end
end
