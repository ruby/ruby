require_relative '../spec_helper'
require_relative 'shared/new'

describe "UNIXServer.new" do
  it_behaves_like :unixserver_new, :new
end
