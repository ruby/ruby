require_relative '../../spec_helper'
require 'etc'

describe "Struct::Group" do
  platform_is_not :windows do
    grpname = IO.popen(%w'id -gn', err: IO::NULL, &:read)
    next unless $?.success?
    grpname.chomp!

    before :all do
      @g = Etc.getgrgid(`id -g`.strip.to_i)
    end

    it "returns group name" do
      @g.name.should == grpname
    end

    it "returns group password" do
      @g.passwd.is_a?(String).should == true
    end

    it "returns group id" do
      @g.gid.should == `id -g`.strip.to_i
    end

    it "returns an array of users belonging to the group" do
      @g.mem.is_a?(Array).should == true
    end

    it "can be compared to another object" do
      (@g == nil).should == false
      (@g == Object.new).should == false
    end
  end
end
