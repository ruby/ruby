require_relative '../../spec_helper'
require 'etc'

describe "Etc::Passwd" do
  platform_is_not :windows do
    before :all do
      @pw = Etc.getpwuid(`id -u`.strip.to_i)
    end

    it "returns user name" do
      @pw.name.should == `id -un`.strip
    end

    it "returns user password" do
      @pw.passwd.is_a?(String).should == true
    end

    it "returns user id" do
      @pw.uid.should == `id -u`.strip.to_i
    end

    it "returns user group id" do
      # There is a mismatch between the group IDs of "id -g" and C function
      # getpwuid(uid_t uid) pw_gid
      # https://github.com/IBM/actionspz/issues/31
      if ENV["GITHUB_ACTIONS"] && RUBY_PLATFORM =~ /ppc64le|s390x/
        skip 'There is a mismatch between "id -g" and getpwuid() pw_gid'
      end

      @pw.gid.should == `id -g`.strip.to_i
    end

    it "returns user personal information (gecos field)" do
      @pw.gecos.is_a?(String).should == true
    end

    it "returns user home directory" do
      @pw.dir.is_a?(String).should == true
    end

    it "returns user shell" do
      @pw.shell.is_a?(String).should == true
    end

    it "can be compared to another object" do
      (@pw == nil).should == false
      (@pw == Object.new).should == false
    end
  end
end
