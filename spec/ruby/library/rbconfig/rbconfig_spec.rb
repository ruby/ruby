require_relative '../../spec_helper'
require 'rbconfig'

describe 'RbConfig::CONFIG' do
  it 'values are all strings' do
    RbConfig::CONFIG.each do |k, v|
      k.should be_kind_of String
      v.should be_kind_of String
    end
  end

  # These directories have no meanings before the installation.
  guard -> { RbConfig::TOPDIR } do
    it "['rubylibdir'] returns the directory containing Ruby standard libraries" do
      rubylibdir = RbConfig::CONFIG['rubylibdir']
      File.directory?(rubylibdir).should == true
      File.should.exist?("#{rubylibdir}/fileutils.rb")
    end

    it "['archdir'] returns the directory containing standard libraries C extensions" do
      archdir = RbConfig::CONFIG['archdir']
      File.directory?(archdir).should == true
      File.should.exist?("#{archdir}/etc.#{RbConfig::CONFIG['DLEXT']}")
    end

    it "['sitelibdir'] is set and is part of $LOAD_PATH" do
      sitelibdir = RbConfig::CONFIG['sitelibdir']
      sitelibdir.should be_kind_of String
      $LOAD_PATH.map{|path| File.realpath(path) rescue path }.should.include? sitelibdir
    end
  end

  it "contains no frozen strings even with --enable-frozen-string-literal" do
    ruby_exe(<<-RUBY, options: '--enable-frozen-string-literal').should == "Done\n"
      require 'rbconfig'
      RbConfig::CONFIG.each do |k, v|
        if v.frozen?
          puts "\#{k} Failure"
        end
      end
      puts 'Done'
    RUBY
  end

  platform_is_not :windows do
    it "['LIBRUBY'] is the same as LIBRUBY_SO if and only if ENABLE_SHARED" do
      case RbConfig::CONFIG['ENABLE_SHARED']
      when 'yes'
        RbConfig::CONFIG['LIBRUBY'].should == RbConfig::CONFIG['LIBRUBY_SO']
      when 'no'
        RbConfig::CONFIG['LIBRUBY'].should_not == RbConfig::CONFIG['LIBRUBY_SO']
      end
    end
  end

  guard -> { RbConfig::TOPDIR } do
    it "libdir/LIBRUBY_SO is the path to libruby and it exists if and only if ENABLE_SHARED" do
      libdirname = RbConfig::CONFIG['LIBPATHENV'] == 'PATH' ? 'bindir' :
                     RbConfig::CONFIG['libdirname']
      libdir = RbConfig::CONFIG[libdirname]
      libruby_so = "#{libdir}/#{RbConfig::CONFIG['LIBRUBY_SO']}"
      case RbConfig::CONFIG['ENABLE_SHARED']
      when 'yes'
        File.should.exist?(libruby_so)
      when 'no'
        File.should_not.exist?(libruby_so)
      end
    end
  end

  platform_is :linux do
    it "['AR'] exists and can be executed" do
      ar = RbConfig::CONFIG.fetch('AR')
      out = `#{ar} --version`
      $?.should.success?
      out.should_not be_empty
    end

    it "['STRIP'] exists and can be executed" do
      strip = RbConfig::CONFIG.fetch('STRIP')
      copy = tmp("sh")
      cp '/bin/sh', copy
      begin
        out = `#{strip} #{copy}`
        $?.should.success?
      ensure
        rm_r copy
      end
    end
  end

  guard -> { %w[aarch64 arm64].include? RbConfig::CONFIG['host_cpu'] } do
    it "['host_cpu'] returns CPU architecture properly for AArch64" do
      platform_is :darwin do
        RbConfig::CONFIG['host_cpu'].should == 'arm64'
      end

      platform_is_not :darwin do
        RbConfig::CONFIG['host_cpu'].should == 'aarch64'
      end
    end
  end

  guard -> { platform_is(:linux) || platform_is(:darwin) } do
    it "['host_os'] returns a proper OS name or platform" do
      platform_is :darwin do
        RbConfig::CONFIG['host_os'].should.match?(/darwin/)
      end

      platform_is :linux do
        RbConfig::CONFIG['host_os'].should.match?(/linux/)
      end
    end
  end
end

describe "RbConfig::TOPDIR" do
  it "either returns nil (if not installed) or the prefix" do
    if RbConfig::TOPDIR
      RbConfig::TOPDIR.should == RbConfig::CONFIG["prefix"]
    else
      RbConfig::TOPDIR.should == nil
    end
  end
end

describe "RUBY_PLATFORM" do
  it "RUBY_PLATFORM contains a proper CPU architecture" do
    RUBY_PLATFORM.should.include? RbConfig::CONFIG['host_cpu']
  end

  guard -> { platform_is(:linux) || platform_is(:darwin) } do
    it "RUBY_PLATFORM contains OS name" do
      # don't use RbConfig::CONFIG['host_os'] as far as it could be slightly different, e.g. linux-gnu
      platform_is(:linux) do
        RUBY_PLATFORM.should.include? 'linux'
      end

      platform_is(:darwin) do
        RUBY_PLATFORM.should.include? 'darwin'
      end
    end
  end
end

describe "RUBY_DESCRIPTION" do
  it "contains version" do
    RUBY_DESCRIPTION.should.include? RUBY_VERSION
  end

  it "contains RUBY_PLATFORM" do
    RUBY_DESCRIPTION.should.include? RUBY_PLATFORM
  end
end
