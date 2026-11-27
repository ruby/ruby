require_relative '../../spec_helper'
require 'etc'

platform_is :windows do
  describe "Etc.getlogin" do
    it "returns the name associated with the current login activity" do
      # The login name is determined when the process starts, from ENV['USER'],
      # ENV['USERNAME'] or GetUserName(), and ENV['USER'] is set from it.
      Etc.getlogin.should == ENV['USER']
    end
  end
end

platform_is_not :windows do
  describe "Etc.getlogin" do
    it "returns the name associated with the current login activity" do
      getlogin_null = false

      # POSIX logname(1) shows getlogin(2)'s result
      # NOTE: Etc.getlogin returns ENV['USER'] if getlogin(2) returns NULL
      begin
        # make Etc.getlogin to return nil if getlogin(3) returns NULL
        envuser, ENV['USER'] = ENV['USER'], nil
        if Etc.getlogin
          if ENV['TRAVIS'] and platform_is(:darwin)
            # See https://travis-ci.org/ruby/spec/jobs/285967744
            # and https://travis-ci.org/ruby/spec/jobs/285999602
            Etc.getlogin.should.instance_of?(String)
          else
            # Etc.getlogin returns the same result of logname(2)
            # if it returns non NULL
            logname = [%w[logname], %w[id -un]].find do |cmd|
              name = IO.popen(cmd, err: File::NULL, &:read) rescue next
              break name.chomp if $?.success?
            end
            if logname
              Etc.getlogin.should == logname
            end
          end
        else
          # Etc.getlogin may return nil if the login name is not set
          # because of chroot or sudo or something.
          Etc.getlogin.should == nil
          getlogin_null = true
        end
      ensure
        ENV['USER'] = envuser
      end

      # if getlogin(2) returns NULL, Etc.getlogin returns ENV['USER']
      if getlogin_null
        Etc.getlogin.should == ENV['USER']
      end
    end
  end
end
