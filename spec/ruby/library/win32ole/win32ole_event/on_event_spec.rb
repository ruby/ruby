require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::MSXML_AVAILABLE } do

    def handler_global(event, *args)
      @event_global += event
    end

    def handler_specific(*args)
      @event_specific = "specific"
    end

    def handler_spec_alt(*args)
      @event_spec_alt = "spec_alt"
    end

    describe "WIN32OLE_EVENT#on_event" do
      before :all do
        @fn_xml = File.absolute_path "../fixtures/event.xml", __dir__
      end

      before :each do
        @xml_dom = WIN32OLESpecs.new_ole 'MSXML.DOMDocument'
        @xml_dom.async = true
        @ev = WIN32OLE_EVENT.new @xml_dom
        @event_global   = ''
        @event_specific = ''
        @event_spec_alt = ''
      end

      after :each do
        @xml_dom = nil
        @ev = nil
      end

      it "sets global event handler properly, and the handler is invoked by event loop" do
        @ev.on_event { |*args| handler_global(*args) }
        @xml_dom.loadXML "<program><name>Ruby</name><version>trunk</version></program>"
        WIN32OLE_EVENT.message_loop
        @event_global.should =~ /onreadystatechange/
      end

      it "accepts a String argument and the handler is invoked by event loop" do
        @ev.on_event("onreadystatechange") { |*args| @event = 'foo' }
        @xml_dom.loadXML "<program><name>Ruby</name><version>trunk</version></program>"
        WIN32OLE_EVENT.message_loop
        @event.should =~ /foo/
      end

      it "accepts a Symbol argument and the handler is invoked by event loop" do
        @ev.on_event(:onreadystatechange) { |*args| @event = 'bar' }
        @xml_dom.loadXML "<program><name>Ruby</name><version>trunk</version></program>"
        WIN32OLE_EVENT.message_loop
        @event.should =~ /bar/
      end

      it "accepts a specific event handler and overrides a global event handler" do
        @ev.on_event                       { |*args| handler_global(*args)   }
        @ev.on_event("onreadystatechange") { |*args| handler_specific(*args) }
        @ev.on_event("onreadystatechange") { |*args| handler_spec_alt(*args) }
        @xml_dom.load @fn_xml
        WIN32OLE_EVENT.message_loop
        @event_global.should == 'ondataavailable'
        @event_global.should_not =~ /onreadystatechange/
        @event_specific.should == ''
        @event_spec_alt.should == "spec_alt"
      end
    end
  end
ensure
  $VERBOSE = verbose
end
