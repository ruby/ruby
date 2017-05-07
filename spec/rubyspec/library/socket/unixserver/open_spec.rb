require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../shared/new', __FILE__)

describe "UNIXServer.open" do
  it_behaves_like :unixserver_new, :open

  platform_is_not :windows do
    before :each do
      @path = tmp("unixserver_spec")
      rm_r @path
    end

    after :each do
      @server.close if @server
      @server = nil
      rm_r @path
    end

    it "yields the new UNIXServer object to the block, if given" do
      UNIXServer.open(@path) do |unix|
        unix.path.should == @path
        unix.addr.should == ["AF_UNIX", @path]
      end
    end
  end
end
