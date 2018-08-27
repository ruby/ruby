require File.expand_path('../../../spec_helper', __FILE__)
require 'etc'

platform_is_not :windows do
  describe "Etc.passwd" do
    it "returns a Etc::Passwd struct" do
      passwd = Etc.passwd
      begin
        passwd.should be_an_instance_of(Etc::Passwd)
      ensure
        Etc.endpwent
      end
    end
  end
end
