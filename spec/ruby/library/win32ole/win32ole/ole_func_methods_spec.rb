require_relative '../fixtures/classes'

platform_is :windows do
  require 'win32ole'

  describe "WIN32OLE#ole_func_methods" do
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
          $stderr.puts "WIN32OLE#ole_func_methods retry (#{tries}): #{e.class}: #{e.message}"
          retry
        end
      end
    end

    after :each do
      @ie.Quit if @ie
    end

    it "raises ArgumentError if argument is given" do
      lambda { @ie.ole_func_methods(1) }.should raise_error ArgumentError
    end

    it "returns an array of WIN32OLE_METHODs" do
      @ie.ole_func_methods.all? { |m| m.kind_of? WIN32OLE_METHOD }.should be_true
    end

    it "contains a 'AddRef' method for Internet Explorer" do
      @ie.ole_func_methods.map { |m| m.name }.include?('AddRef').should be_true
    end
  end
end
