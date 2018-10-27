platform_is :windows do
  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    describe "WIN32OLE#ole_put_methods" do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "raises ArgumentError if argument is given" do
        lambda { @xml_dom.ole_put_methods(1) }.should raise_error ArgumentError
      end

      it "returns an array of WIN32OLE_METHODs" do
        @xml_dom.ole_put_methods.all? { |m| m.kind_of? WIN32OLE_METHOD }.should be_true
      end

      it "contains a 'preserveWhiteSpace' method" do
        @xml_dom.ole_put_methods.map { |m| m.name }.include?('preserveWhiteSpace').should be_true
      end
    end
  end
end
