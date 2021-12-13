require_relative '../../dir/fixtures/common'

describe :file_read_directory, shared: true do
  platform_is :darwin, :linux, :freebsd, :openbsd, :windows do
    it "raises an Errno::EISDIR when passed a path that is a directory" do
      -> { @object.send(@method, ".") }.should raise_error(Errno::EISDIR)
    end
  end

  platform_is :netbsd do
    it "does not raises any exception when passed a path that is a directory" do
      -> { @object.send(@method, ".") }.should_not raise_error
    end
  end
end
