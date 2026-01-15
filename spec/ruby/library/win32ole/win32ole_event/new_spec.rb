require_relative "../../../spec_helper"
platform_is :windows do
  require_relative '../fixtures/classes'

  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do
    describe "WIN32OLE::Event.new" do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "raises TypeError given invalid argument" do
        -> { WIN32OLE::Event.new "A" }.should raise_error TypeError
      end

      it "raises RuntimeError if event does not exist" do
        -> { WIN32OLE::Event.new(@xml_dom, 'A') }.should raise_error RuntimeError
      end

      it "raises RuntimeError if OLE object has no events" do
        dict = WIN32OLESpecs.new_ole('Scripting.Dictionary')
        -> { WIN32OLE::Event.new(dict) }.should raise_error RuntimeError
      end

      it "creates WIN32OLE::Event object" do
        ev = WIN32OLE::Event.new(@xml_dom)
        ev.should be_kind_of WIN32OLE::Event
      end
    end
  end
end
