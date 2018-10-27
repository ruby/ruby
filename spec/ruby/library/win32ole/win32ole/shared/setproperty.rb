platform_is :windows do
  require_relative '../../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    describe :win32ole_setproperty, shared: true do
      before :all do
        @xml_dom = WIN32OLESpecs.new_ole('MSXML.DOMDocument')
      end

      after :all do
        @xml_dom = nil
      end

      it "raises ArgumentError if no argument is given" do
        lambda { @xml_dom.send(@method) }.should raise_error ArgumentError
      end

      it "sets async true and returns nil" do
        result = @xml_dom.send(@method, 'async', true)
        result.should == nil
      end
    end
  end
end
