require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)

platform_is_not :windows do
  describe "UNIXServer#for_fd" do
    before :each do
      @unix_path = tmp("unix_socket")
      @unix = UNIXServer.new(@unix_path)
    end

    after :each do
      @unix.close if @unix
      rm_r @unix_path
    end

    it "can calculate the path" do
      b = UNIXServer.for_fd(@unix.fileno)
      b.autoclose = false

      b.path.should == @unix_path
    end
  end
end
