platform_is :windows do
  require_relative '../../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    describe :win32ole_ole_method, shared: true do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "raises ArgumentError if no argument is given" do
        lambda { @xml_dom.send(@method) }.should raise_error ArgumentError
      end

      it "returns the WIN32OLE_METHOD 'abort' if given 'abort'" do
        result = @xml_dom.send(@method, "abort")
        result.kind_of?(WIN32OLE_METHOD).should be_true
        result.name.should == 'abort'
      end
    end
  end
end
