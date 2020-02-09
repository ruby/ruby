require_relative '../../spec_helper'

describe "File.utime" do

  before :all do
    @time_is_float = /mswin|mingw/ =~ RUBY_PLATFORM && RUBY_VERSION >= '2.5'
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
    File.utime(@atime, @mtime, @file1, @file2)
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
    File.utime(nil, nil, @file1, @file2)
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
    File.utime(@atime, @mtime, mock_to_path(@file1), mock_to_path(@file2))
  end

  it "accepts numeric atime and mtime arguments" do
    if @time_is_float
      File.utime(@atime.to_f, @mtime.to_f, @file1, @file2)
      File.atime(@file1).should be_close(@atime, 0.0001)
      File.mtime(@file1).should be_close(@mtime, 0.0001)
      File.atime(@file2).should be_close(@atime, 0.0001)
      File.mtime(@file2).should be_close(@mtime, 0.0001)
    else
      File.utime(@atime.to_i, @mtime.to_i, @file1, @file2)
      File.atime(@file1).to_i.should be_close(@atime.to_i, TIME_TOLERANCE)
      File.mtime(@file1).to_i.should be_close(@mtime.to_i, TIME_TOLERANCE)
      File.atime(@file2).to_i.should be_close(@atime.to_i, TIME_TOLERANCE)
      File.mtime(@file2).to_i.should be_close(@mtime.to_i, TIME_TOLERANCE)
    end
  end

  platform_is :linux do
    platform_is wordsize: 64 do
      it "allows Time instances in the far future to set mtime and atime (but some filesystems limit it up to 2446-05-10)" do
        # https://ext4.wiki.kernel.org/index.php/Ext4_Disk_Layout#Inode_Timestamps
        # "Therefore, timestamps should not overflow until May 2446."
        time = Time.at(1<<44)
        File.utime(time, time, @file1)
        [559444, 2446].should.include? File.atime(@file1).year
        [559444, 2446].should.include? File.mtime(@file1).year
      end
    end
  end
end
