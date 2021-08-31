require_relative '../../spec_helper'

describe "File.lchmod" do
  platform_is_not :linux, :windows, :openbsd, :solaris, :aix do
    before :each do
      @fname = tmp('file_chmod_test')
      @lname = @fname + '.lnk'

      touch(@fname) { |f| f.write "rubinius" }

      rm_r @lname
      File.symlink @fname, @lname
    end

    after :each do
      rm_r @lname, @fname
    end

    it "changes the file mode of the link and not of the file" do
      File.chmod(0222, @lname).should == 1
      File.lchmod(0755, @lname).should == 1

      File.lstat(@lname).should.executable?
      File.lstat(@lname).should.readable?
      File.lstat(@lname).should.writable?

      File.stat(@lname).should_not.executable?
      File.stat(@lname).should_not.readable?
      File.stat(@lname).should.writable?
    end
  end
end
