require_relative '../spec_helper'
require_relative 'shared/new'

with_feature :unix_socket do
  describe "UNIXServer.new" do
    it_behaves_like :unixserver_new, :new

    it "does not use the given block and warns to use UNIXServer::open" do
      -> {
        @server = UNIXServer.new(@path) { raise }
      }.should complain(/warning: UNIXServer::new\(\) does not take block; use UNIXServer::open\(\) instead/)
    end
  end
end
