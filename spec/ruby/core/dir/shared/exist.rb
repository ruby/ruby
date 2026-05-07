describe :dir_exist, shared: true do
  it "returns true if the given directory exists" do
    Dir.send(@method, __dir__).should == true
  end

  it "returns true for '.'" do
    Dir.send(@method, '.').should == true
  end

  it "returns true for '..'" do
    Dir.send(@method, '..').should == true
  end

  it "understands non-ASCII paths" do
    subdir = File.join(tmp("\u{9876}\u{665}"))
    Dir.send(@method, subdir).should == false
    Dir.mkdir(subdir)
    Dir.send(@method, subdir).should == true
    Dir.rmdir(subdir)
  end

  it "understands relative paths" do
    Dir.send(@method, __dir__ + '/../').should == true
  end

  it "returns false if the given directory doesn't exist" do
    Dir.send(@method, 'y26dg27n2nwjs8a/').should == false
  end

  it "doesn't require the name to have a trailing slash" do
    dir = __dir__
    dir.sub!(/\/$/,'')
    Dir.send(@method, dir).should == true
  end

  it "doesn't expand paths" do
    skip "$HOME not valid directory" unless ENV['HOME'] && File.directory?(ENV['HOME'])
    Dir.send(@method, File.expand_path('~')).should == true
    Dir.send(@method, '~').should == false
  end

  it "returns false if the argument exists but is a file" do
    File.should.exist?(__FILE__)
    Dir.send(@method, __FILE__).should == false
  end

  it "doesn't set $! when file doesn't exist" do
    Dir.send(@method, "/path/to/non/existent/dir")
    $!.should == nil
  end

  it "calls #to_path on non String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return(__dir__)
    Dir.send(@method, p)
  end
end
