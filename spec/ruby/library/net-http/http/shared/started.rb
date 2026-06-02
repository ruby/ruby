describe :net_http_started_p, shared: true do
  before :each do
    NetHTTPSpecs.start_server
    @http = Net::HTTP.new("localhost", NetHTTPSpecs.port)
  end

  after :each do
    @http.finish if @http.started?
    NetHTTPSpecs.stop_server
  end

  it "returns true when self has been started" do
    @http.start
    @http.send(@method).should == true
  end

  it "returns false when self has not been started yet" do
    @http.send(@method).should == false
  end

  it "returns false when self has been stopped again" do
    @http.start
    @http.finish
    @http.send(@method).should == false
  end
end
