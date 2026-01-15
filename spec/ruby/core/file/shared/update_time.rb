describe :update_time, shared: true do
  before :all do
    @time_is_float = platform_is :windows
  end

  before :each do
    @atime = Time.now
    @mtime = Time.now
    @file1 = tmp("specs_file_utime1")
    @file2 = tmp("specs_file_utime2")
    touch @file1
    touch @file2
  end

  after :each do
    rm_r @file1, @file2
  end

  it "sets the access and modification time of each file" do
    File.send(@method, @atime, @mtime, @file1, @file2)

    if @time_is_float
      File.atime(@file1).should be_close(@atime, 0.0001)
      File.mtime(@file1).should be_close(@mtime, 0.0001)
      File.atime(@file2).should be_close(@atime, 0.0001)
      File.mtime(@file2).should be_close(@mtime, 0.0001)
    else
      File.atime(@file1).to_i.should be_close(@atime.to_i, TIME_TOLERANCE)
      File.mtime(@file1).to_i.should be_close(@mtime.to_i, TIME_TOLERANCE)
      File.atime(@file2).to_i.should be_close(@atime.to_i, TIME_TOLERANCE)
      File.mtime(@file2).to_i.should be_close(@mtime.to_i, TIME_TOLERANCE)
    end
  end

  it "uses the current times if two nil values are passed" do
    tn = Time.now
    File.send(@method, nil, nil, @file1, @file2)

    if @time_is_float
      File.atime(@file1).should be_close(tn, 0.050)
      File.mtime(@file1).should be_close(tn, 0.050)
      File.atime(@file2).should be_close(tn, 0.050)
      File.mtime(@file2).should be_close(tn, 0.050)
    else
      File.atime(@file1).to_i.should be_close(Time.now.to_i, TIME_TOLERANCE)
      File.mtime(@file1).to_i.should be_close(Time.now.to_i, TIME_TOLERANCE)
      File.atime(@file2).to_i.should be_close(Time.now.to_i, TIME_TOLERANCE)
      File.mtime(@file2).to_i.should be_close(Time.now.to_i, TIME_TOLERANCE)
    end
  end

  it "accepts an object that has a #to_path method" do
    File.send(@method, @atime, @mtime, mock_to_path(@file1), mock_to_path(@file2))
  end

  it "accepts numeric atime and mtime arguments" do
    if @time_is_float
      File.send(@method, @atime.to_f, @mtime.to_f, @file1, @file2)

      File.atime(@file1).should be_close(@atime, 0.0001)
      File.mtime(@file1).should be_close(@mtime, 0.0001)
      File.atime(@file2).should be_close(@atime, 0.0001)
      File.mtime(@file2).should be_close(@mtime, 0.0001)
    else
      File.send(@method, @atime.to_i, @mtime.to_i, @file1, @file2)

      File.atime(@file1).to_i.should be_close(@atime.to_i, TIME_TOLERANCE)
      File.mtime(@file1).to_i.should be_close(@mtime.to_i, TIME_TOLERANCE)
      File.atime(@file2).to_i.should be_close(@atime.to_i, TIME_TOLERANCE)
      File.mtime(@file2).to_i.should be_close(@mtime.to_i, TIME_TOLERANCE)
    end
  end

  it "may set nanosecond precision" do
    t = Time.utc(2007, 11, 1, 15, 25, 0, 123456.789r)
    File.send(@method, t, t, @file1)

    File.atime(@file1).nsec.should.between?(0, 123500000)
    File.mtime(@file1).nsec.should.between?(0, 123500000)
  end

  it "returns the number of filenames in the arguments" do
    File.send(@method, @atime.to_f, @mtime.to_f, @file1, @file2).should == 2
  end

  platform_is :linux do
    platform_is pointer_size: 64 do
      it "allows Time instances in the far future to set mtime and atime (but some filesystems limit it up to 2446-05-10 or 2038-01-19 or 2486-07-02)" do
        # https://ext4.wiki.kernel.org/index.php/Ext4_Disk_Layout#Inode_Timestamps
        # "Therefore, timestamps should not overflow until May 2446."
        # https://lwn.net/Articles/804382/
        # "On-disk timestamps hitting the y2038 limit..."
        # The problem seems to be being improved, but currently it actually fails on XFS on RHEL8
        # https://rubyci.org/logs/rubyci.s3.amazonaws.com/rhel8/ruby-master/log/20201112T123004Z.fail.html.gz
        # Amazon Linux 2023 returns 2486-07-02 in this example
        # http://rubyci.s3.amazonaws.com/amazon2023/ruby-master/log/20230322T063004Z.fail.html.gz
        time = Time.at(1<<44)
        File.send(@method, time, time, @file1)

        [559444, 2486, 2446, 2038].should.include? File.atime(@file1).year
        [559444, 2486, 2446, 2038].should.include? File.mtime(@file1).year
      end
    end
  end
end
