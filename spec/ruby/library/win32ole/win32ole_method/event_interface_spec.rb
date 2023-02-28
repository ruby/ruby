require_relative "../../../spec_helper"
platform_is :windows do
  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::SYSTEM_MONITOR_CONTROL_AVAILABLE } do

    describe "WIN32OLE_METHOD#event_interface" do
      before :each do
        ole_type = WIN32OLE_TYPE.new("System Monitor Control", "SystemMonitor")
        @on_dbl_click_method = WIN32OLE_METHOD.new(ole_type, "OnDblClick")
        ole_type = WIN32OLE_TYPE.new("Microsoft Shell Controls And Automation", "Shell")
        @namespace_method = WIN32OLE_METHOD.new(ole_type, "namespace")
      end

      it "raises ArgumentError if argument is given" do
        -> { @on_dbl_click_method.event_interface(1) }.should raise_error ArgumentError
      end

      it "returns expected string for System Monitor Control's 'OnDblClick' method" do
        @on_dbl_click_method.event_interface.should == "DISystemMonitorEvents"
      end

      it "returns nil if method has no event interface" do
        @namespace_method.event_interface.should be_nil
      end

    end
  end

end
