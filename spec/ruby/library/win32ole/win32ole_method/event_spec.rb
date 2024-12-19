require_relative "../../../spec_helper"
platform_is :windows do
  verbose, $VERBOSE = $VERBOSE, nil

  require_relative '../fixtures/classes'
  guard -> { WIN32OLESpecs::SYSTEM_MONITOR_CONTROL_AVAILABLE } do

    describe "WIN32OLE_METHOD#event?" do
      before :each do
        ole_type = WIN32OLE_TYPE.new("System Monitor Control", "SystemMonitor")
        @on_dbl_click_method = WIN32OLE_METHOD.new(ole_type, "OnDblClick")
      end

      it "raises ArgumentError if argument is given" do
        -> { @on_dbl_click_method.event?(1) }.should raise_error ArgumentError
      end

      it "returns true for System Monitor Control's 'OnDblClick' method" do
        @on_dbl_click_method.event?.should be_true
      end

    end
  end

ensure
  $VERBOSE = verbose
end
