require_relative '../../fixtures/classes'

platform_is :windows do
  require 'win32ole'

  describe :win32ole_ole_method, shared: true do
    before :each do
      # This part is unstable, so retrying 3 times.
      tries = 0
      begin
        @ie = WIN32OLESpecs.new_ole('InternetExplorer.Application')
      rescue WIN32OLERuntimeError => e
        # WIN32OLERuntimeError: failed to create WIN32OLE object from `InternetExplorer.Application'
        #     HRESULT error code:0x800704a6
        #       A system shutdown has already been scheduled.
        if tries < 3
          tries += 1
          $stderr.puts "win32ole_ole_method retry (#{tries}): #{e.class}: #{e.message}"
          retry
        end
      end
    end

    after :each do
      @ie.Quit
    end

    it "raises ArgumentError if no argument is given" do
      lambda { @ie.send(@method) }.should raise_error ArgumentError
    end

    it "returns the WIN32OLE_METHOD 'Quit' if given 'Quit'" do
      result = @ie.send(@method, "Quit")
      result.kind_of?(WIN32OLE_METHOD).should be_true
      result.name.should == 'Quit'
    end
  end
end
