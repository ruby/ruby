describe :dir_chroot_as_root, shared: true do
  before :all do
    DirSpecs.create_mock_dirs

    @real_root = "../" * (File.dirname(__FILE__).count('/') - 1)
    @ref_dir = File.join("/", File.basename(Dir["/*"].first))
  end

  after :all do
    until File.exist?(@ref_dir)
      Dir.send(@method, "../") or break
    end

    DirSpecs.delete_mock_dirs
  end

  # Pending until https://github.com/ruby/ruby/runs/8075149420 is fixed
  compilations_ci = ENV["GITHUB_WORKFLOW"] == "Compilations"

  it "can be used to change the process' root directory" do
    -> { Dir.send(@method, File.dirname(__FILE__)) }.should_not raise_error
    File.should.exist?("/#{File.basename(__FILE__)}")
  end unless compilations_ci

  it "returns 0 if successful" do
    Dir.send(@method, '/').should == 0
  end

  it "raises an Errno::ENOENT exception if the directory doesn't exist" do
    -> { Dir.send(@method, 'xgwhwhsjai2222jg') }.should raise_error(Errno::ENOENT)
  end

  it "can be escaped from with ../" do
    Dir.send(@method, @real_root)
    File.should.exist?(@ref_dir)
    File.should_not.exist?("/#{File.basename(__FILE__)}")
  end unless compilations_ci

  it "calls #to_path on non-String argument" do
    p = mock('path')
    p.should_receive(:to_path).and_return(@real_root)
    Dir.send(@method, p)
  end
end
