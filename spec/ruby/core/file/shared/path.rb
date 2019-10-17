describe :file_path, shared: true do
  before :each do
    @name = "file_to_path"
    @path = tmp(@name)
    touch @path
  end

  after :each do
    @file.close if @file and !@file.closed?
    rm_r @path
  end

  it "returns a String" do
    @file = File.new @path
    @file.send(@method).should be_an_instance_of(String)
  end

  it "calls to_str on argument and returns exact value" do
    path = mock('path')
    path.should_receive(:to_str).and_return(@path)
    @file = File.new path
    @file.send(@method).should == @path
  end

  it "does not normalise the path it returns" do
    Dir.chdir(tmp("")) do
      unorm = "./#{@name}"
      @file = File.new unorm
      @file.send(@method).should == unorm
    end
  end

  it "does not canonicalize the path it returns" do
    dir = File.basename tmp("")
    path = "#{tmp("")}../#{dir}/#{@name}"
    @file = File.new path
    @file.send(@method).should == path
  end

  it "does not absolute-ise the path it returns" do
    Dir.chdir(tmp("")) do
      @file = File.new @name
      @file.send(@method).should == @name
    end
  end

  it "preserves the encoding of the path" do
    path = @path.force_encoding("euc-jp")
    @file = File.new path
    @file.send(@method).encoding.should == Encoding.find("euc-jp")
  end

  ruby_version_is "2.5" do
    platform_is :linux do
      guard -> { defined?(File::TMPFILE) } do
        before :each do
          @dir = tmp("tmpfilespec")
          mkdir_p @dir
        end

        after :each do
          rm_r @dir
        end

        it "raises IOError if file was opened with File::TMPFILE" do
          begin
            File.open(@dir, File::RDWR | File::TMPFILE) do |f|
              -> { f.send(@method) }.should raise_error(IOError)
            end
          rescue Errno::EOPNOTSUPP, Errno::EINVAL, Errno::EISDIR
            skip "no support from the filesystem"
          end
        end
      end
    end
  end
end
