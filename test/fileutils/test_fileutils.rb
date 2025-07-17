# frozen_string_literal: true
# $Id$

require 'fileutils'
require 'etc'
require_relative 'fileasserts'
require 'pathname'
require 'tmpdir'
require 'stringio'
require 'test/unit'

class TestFileUtils < Test::Unit::TestCase
  include Test::Unit::FileAssertions

  def assert_output_lines(expected, fu = self, message=nil)
    old = fu.instance_variables.include?(:@fileutils_output) && fu.instance_variable_get(:@fileutils_output)
    IO.pipe {|read, write|
      fu.instance_variable_set(:@fileutils_output, write)
      th = Thread.new { read.read }
      th2 = Thread.new {
        begin
          yield
        ensure
          write.close
        end
      }
      th_value, _ = assert_join_threads([th, th2])
      lines = th_value.lines.map {|l| l.chomp }
      assert_equal(expected, lines)
    }
  ensure
    fu.instance_variable_set(:@fileutils_output, old) if old
  end

  m = Module.new do
    def have_drive_letter?
      /mswin(?!ce)|mingw|bcc|emx/ =~ RUBY_PLATFORM
    end

    def have_file_perm?
      /mswin|mingw|bcc|emx/ !~ RUBY_PLATFORM
    end

    @@have_symlink = nil

    def have_symlink?
      if @@have_symlink == nil
        @@have_symlink = check_have_symlink?
      end
      @@have_symlink
    end

    def check_have_symlink?
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.symlink "symlink", "symlink"
        end
      end
    rescue NotImplementedError, Errno::EACCES
      return false
    rescue
      return true
    end

    @@have_hardlink = nil

    def have_hardlink?
      if @@have_hardlink == nil
        @@have_hardlink = check_have_hardlink?
      end
      @@have_hardlink
    end

    def check_have_hardlink?
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write "dummy", "dummy"
          File.link "dummy", "hardlink"
        end
      end
    rescue NotImplementedError, Errno::EACCES
      return false
    rescue
      return true
    end

    @@no_broken_symlink = false
    if /cygwin/ =~ RUBY_PLATFORM and /\bwinsymlinks:native(?:strict)?\b/ =~ ENV["CYGWIN"]
      @@no_broken_symlink = true
    end

    def no_broken_symlink?
      @@no_broken_symlink
    end

    def has_capsh?
      !!system('capsh', '--print', out: File::NULL, err: File::NULL)
    end

    def has_root_file_capabilities?
      !!system(
        'capsh', '--has-p=CAP_DAC_OVERRIDE', '--has-p=CAP_CHOWN', '--has-p=CAP_FOWNER',
        out: File::NULL, err: File::NULL
      )
    end

    def root_in_posix?
      if /cygwin/ =~ RUBY_PLATFORM
        # FIXME: privilege if groups include root user?
        return Process.groups.include?(0)
      elsif has_capsh?
        return has_root_file_capabilities?
      elsif Process.respond_to?('uid')
        return Process.uid == 0
      else
        return false
      end
    end

    def distinct_uids(n = 2)
      return unless user = Etc.getpwent
      uids = [user.uid]
      while user = Etc.getpwent
        uid = user.uid
        unless uids.include?(uid)
          uids << uid
          break if uids.size >= n
        end
      end
      uids
    ensure
      Etc.endpwent
    end

    begin
      tmproot = Dir.mktmpdir "fileutils"
      Dir.chdir tmproot do
        Dir.mkdir("\n")
        Dir.rmdir("\n")
      end
      def lf_in_path_allowed?
        true
      end
    rescue
      def lf_in_path_allowed?
        false
      end
    ensure
      begin
        Dir.rmdir tmproot
      rescue
        STDERR.puts $!.inspect
        STDERR.puts Dir.entries(tmproot).inspect
      end
    end
  end
  include m
  extend m

  UID_1, UID_2 = distinct_uids(2)

  include FileUtils

  def check_singleton(name)
    assert_respond_to ::FileUtils, name
  end

  def my_rm_rf(path)
    if File.exist?('/bin/rm')
      system "/bin/rm", "-rf", path
    elsif /mswin|mingw/ =~ RUBY_PLATFORM
      system "rmdir", "/q/s", path.gsub('/', '\\'), err: IO::NULL
    else
      FileUtils.rm_rf path
    end
  end

  def mymkdir(path)
    Dir.mkdir path
    File.chown nil, Process.gid, path if have_file_perm?
  end

  def setup
    @prevdir = Dir.pwd
    @groups = [Process.gid] | Process.groups if have_file_perm?
    tmproot = @tmproot = Dir.mktmpdir "fileutils"
    Dir.chdir tmproot
    my_rm_rf 'data'; mymkdir 'data'
    my_rm_rf 'tmp';  mymkdir 'tmp'
    prepare_data_file
  end

  def teardown
    Dir.chdir @prevdir
    my_rm_rf @tmproot
  end


  TARGETS = %w( data/a data/all data/random data/zero )

  def prepare_data_file
    File.open('data/a', 'w') {|f|
      32.times do
        f.puts 'a' * 50
      end
    }

    all_chars = (0..255).map {|n| n.chr }.join('')
    File.open('data/all', 'w') {|f|
      32.times do
        f.puts all_chars
      end
    }

    random_chars = (0...50).map { rand(256).chr }.join('')
    File.open('data/random', 'w') {|f|
      32.times do
        f.puts random_chars
      end
    }

    File.open('data/zero', 'w') {|f|
      ;
    }
  end

  BIGFILE = 'data/big'

  def prepare_big_file
    File.open('data/big', 'w') {|f|
      (4 * 1024 * 1024 / 256).times do   # 4MB
        f.print "aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa aaaa\n"
      end
    }
  end

  def prepare_time_data
    File.open('data/old',    'w') {|f| f.puts 'dummy' }
    File.open('data/newer',  'w') {|f| f.puts 'dummy' }
    File.open('data/newest', 'w') {|f| f.puts 'dummy' }
    t = Time.now
    File.utime t-8, t-8, 'data/old'
    File.utime t-4, t-4, 'data/newer'
  end

  def each_srcdest
    TARGETS.each do |path|
      yield path, "tmp/#{File.basename(path)}"
    end
  end

  #
  # Test Cases
  #

  def test_assert_output_lines
    assert_raise(Test::Unit::AssertionFailedError) {
      Timeout.timeout(0.5) {
        assert_output_lines([]) {
          Thread.current.report_on_exception = false
          raise "ok"
        }
      }
    }
  end

  def test_pwd
    check_singleton :pwd

    assert_equal Dir.pwd, pwd()

    cwd = Dir.pwd
    root = have_drive_letter? ? 'C:/' : '/'
    cd(root) {
      assert_equal root, pwd()
    }
    assert_equal cwd, pwd()
  end

  def test_cmp
    check_singleton :cmp

    TARGETS.each do |fname|
      assert cmp(fname, fname), 'not same?'
    end
    assert_raise(ArgumentError) {
      cmp TARGETS[0], TARGETS[0], :undefinedoption => true
    }

    # pathname
    touch 'tmp/cmptmp'
    assert_nothing_raised {
      cmp Pathname.new('tmp/cmptmp'), 'tmp/cmptmp'
      cmp 'tmp/cmptmp', Pathname.new('tmp/cmptmp')
      cmp Pathname.new('tmp/cmptmp'), Pathname.new('tmp/cmptmp')
    }
  end

  def test_cp
    check_singleton :cp

    each_srcdest do |srcpath, destpath|
      cp srcpath, destpath
      assert_same_file srcpath, destpath

      cp srcpath, File.dirname(destpath)
      assert_same_file srcpath, destpath

      cp srcpath, File.dirname(destpath) + '/'
      assert_same_file srcpath, destpath

      cp srcpath, destpath, :preserve => true
      assert_same_file srcpath, destpath
      assert_same_entry srcpath, destpath
    end

    assert_raise(Errno::ENOENT) {
      cp 'tmp/cptmp', 'tmp/cptmp_new'
    }
    assert_file_not_exist('tmp/cptmp_new')

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raise(ArgumentError) {
      cp 'tmp/cptmp', 'tmp/cptmp'
    }
  end

  def test_cp_preserve_permissions
    bug4507 = '[ruby-core:35518]'
    touch 'tmp/cptmp'
    chmod 0o755, 'tmp/cptmp'
    cp 'tmp/cptmp', 'tmp/cptmp2'

    assert_equal_filemode('tmp/cptmp', 'tmp/cptmp2', bug4507, mask: ~File.umask)
  end

  def test_cp_preserve_permissions_dir
    bug7246 = '[ruby-core:48603]'
    mkdir 'tmp/cptmp'
    mkdir 'tmp/cptmp/d1'
    chmod 0o745, 'tmp/cptmp/d1'
    mkdir 'tmp/cptmp/d2'
    chmod 0o700, 'tmp/cptmp/d2'
    cp_r 'tmp/cptmp', 'tmp/cptmp2', :preserve => true
    assert_equal_filemode('tmp/cptmp/d1', 'tmp/cptmp2/d1', bug7246)
    assert_equal_filemode('tmp/cptmp/d2', 'tmp/cptmp2/d2', bug7246)
  end

  def test_cp_symlink
    touch 'tmp/cptmp'
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raise(ArgumentError) {
      cp 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    assert_raise(ArgumentError) {
      cp 'tmp/cptmp_symlink', 'tmp/cptmp'
    }
    return if no_broken_symlink?
    # src==dest (3) looped symlink
    File.symlink 'symlink', 'tmp/symlink'
    assert_raise(Errno::ELOOP) {
      cp 'tmp/symlink', 'tmp/symlink'
    }
  end if have_symlink?

  def test_cp_pathname
    # pathname
    touch 'tmp/cptmp'
    assert_nothing_raised {
      cp 'tmp/cptmp', Pathname.new('tmp/tmpdest')
      cp Pathname.new('tmp/cptmp'), 'tmp/tmpdest'
      cp Pathname.new('tmp/cptmp'), Pathname.new('tmp/tmpdest')
      mkdir 'tmp/tmpdir'
      cp ['tmp/cptmp', 'tmp/tmpdest'], Pathname.new('tmp/tmpdir')
    }
  end

  def test_cp_r
    check_singleton :cp_r

    cp_r 'data', 'tmp'
    TARGETS.each do |fname|
      assert_same_file fname, "tmp/#{fname}"
    end

    cp_r 'data', 'tmp2', :preserve => true
    TARGETS.each do |fname|
      assert_same_entry fname, "tmp2/#{File.basename(fname)}"
      assert_same_file fname, "tmp2/#{File.basename(fname)}"
    end

    # a/* -> b/*
    mkdir 'tmp/cpr_src'
    mkdir 'tmp/cpr_dest'
    File.open('tmp/cpr_src/a', 'w') {|f| f.puts 'a' }
    File.open('tmp/cpr_src/b', 'w') {|f| f.puts 'b' }
    File.open('tmp/cpr_src/c', 'w') {|f| f.puts 'c' }
    mkdir 'tmp/cpr_src/d'
    cp_r 'tmp/cpr_src/.', 'tmp/cpr_dest'
    assert_same_file 'tmp/cpr_src/a', 'tmp/cpr_dest/a'
    assert_same_file 'tmp/cpr_src/b', 'tmp/cpr_dest/b'
    assert_same_file 'tmp/cpr_src/c', 'tmp/cpr_dest/c'
    assert_directory 'tmp/cpr_dest/d'
    assert_raise(ArgumentError) do
      cp_r 'tmp/cpr_src', './tmp/cpr_src'
    end
    assert_raise(ArgumentError) do
      cp_r './tmp/cpr_src', 'tmp/cpr_src'
    end
    assert_raise(ArgumentError) do
      cp_r './tmp/cpr_src', File.expand_path('tmp/cpr_src')
    end

    my_rm_rf 'tmp/cpr_src'
    my_rm_rf 'tmp/cpr_dest'

    bug3588 = '[ruby-core:31360]'
    assert_nothing_raised(ArgumentError, bug3588) do
      cp_r 'tmp', 'tmp2'
    end
    assert_directory 'tmp2/tmp'
    assert_raise(ArgumentError, bug3588) do
      cp_r 'tmp2', 'tmp2/new_tmp2'
    end

    bug12892 = '[ruby-core:77885] [Bug #12892]'
    assert_raise(Errno::ENOENT, bug12892) do
      cp_r 'non/existent', 'tmp'
    end
  end

  def test_cp_r_symlink
    # symlink in a directory
    mkdir 'tmp/cpr_src'
    touch 'tmp/cpr_src/SLdest'
    ln_s 'SLdest', 'tmp/cpr_src/symlink'
    cp_r 'tmp/cpr_src', 'tmp/cpr_dest'
    assert_symlink 'tmp/cpr_dest/symlink'
    assert_equal 'SLdest', File.readlink('tmp/cpr_dest/symlink')

    # root is a symlink
    ln_s 'cpr_src', 'tmp/cpr_src2'
    cp_r 'tmp/cpr_src2', 'tmp/cpr_dest2'
    assert_directory 'tmp/cpr_dest2'
    assert_not_symlink 'tmp/cpr_dest2'
    assert_symlink 'tmp/cpr_dest2/symlink'
    assert_equal 'SLdest', File.readlink('tmp/cpr_dest2/symlink')
  end if have_symlink?

  def test_cp_r_symlink_preserve
    mkdir 'tmp/cross'
    mkdir 'tmp/cross/a'
    mkdir 'tmp/cross/b'
    touch 'tmp/cross/a/f'
    touch 'tmp/cross/b/f'
    ln_s '../a/f', 'tmp/cross/b/l'
    ln_s '../b/f', 'tmp/cross/a/l'
    assert_nothing_raised {
      cp_r 'tmp/cross', 'tmp/cross2', :preserve => true
    }
  end if have_symlink? and !no_broken_symlink?

  def test_cp_r_fifo
    Dir.mkdir('tmp/cpr_src')
    File.mkfifo 'tmp/cpr_src/fifo', 0600
    cp_r 'tmp/cpr_src', 'tmp/cpr_dest'
    assert_equal(true, File.pipe?('tmp/cpr_dest/fifo'))
  end if File.respond_to?(:mkfifo)

  def test_cp_r_dev
    devs = Dir['/dev/*']
    chardev = devs.find{|f| File.chardev?(f)}
    blockdev = devs.find{|f| File.blockdev?(f)}
    Dir.mkdir('tmp/cpr_dest')
    assert_raise(RuntimeError) { cp_r chardev, 'tmp/cpr_dest/cd' } if chardev
    assert_raise(RuntimeError) { cp_r blockdev, 'tmp/cpr_dest/bd' } if blockdev
  end

  begin
    require 'socket'
  rescue LoadError
  else
    def test_cp_r_socket
      pend "Skipping socket test on JRuby" if RUBY_ENGINE == 'jruby'

      Dir.mkdir('tmp/cpr_src')
      UNIXServer.new('tmp/cpr_src/socket').close
      cp_r 'tmp/cpr_src', 'tmp/cpr_dest'
      assert_equal(true, File.socket?('tmp/cpr_dest/socket'))
    rescue Errno::EINVAL => error
      # On some platforms (windows) sockets cannot be copied by FileUtils.
      omit error.message
    end if defined?(UNIXServer)
  end

  def test_cp_r_pathname
    # pathname
    touch 'tmp/cprtmp'
    assert_nothing_raised {
      cp_r Pathname.new('tmp/cprtmp'), 'tmp/tmpdest'
      cp_r 'tmp/cprtmp', Pathname.new('tmp/tmpdest')
      cp_r Pathname.new('tmp/cprtmp'), Pathname.new('tmp/tmpdest')
    }
  end

  def test_cp_r_symlink_remove_destination
    Dir.mkdir 'tmp/src'
    Dir.mkdir 'tmp/dest'
    Dir.mkdir 'tmp/src/dir'
    File.symlink 'tmp/src/dir', 'tmp/src/a'
    cp_r 'tmp/src', 'tmp/dest/', remove_destination: true
    cp_r 'tmp/src', 'tmp/dest/', remove_destination: true
  end if have_symlink?

  def test_cp_lr
    check_singleton :cp_lr

    cp_lr 'data', 'tmp'
    TARGETS.each do |fname|
      assert_same_file fname, "tmp/#{fname}"
    end

    # a/* -> b/*
    mkdir 'tmp/cpr_src'
    mkdir 'tmp/cpr_dest'
    File.open('tmp/cpr_src/a', 'w') {|f| f.puts 'a' }
    File.open('tmp/cpr_src/b', 'w') {|f| f.puts 'b' }
    File.open('tmp/cpr_src/c', 'w') {|f| f.puts 'c' }
    mkdir 'tmp/cpr_src/d'
    cp_lr 'tmp/cpr_src/.', 'tmp/cpr_dest'
    assert_same_file 'tmp/cpr_src/a', 'tmp/cpr_dest/a'
    assert_same_file 'tmp/cpr_src/b', 'tmp/cpr_dest/b'
    assert_same_file 'tmp/cpr_src/c', 'tmp/cpr_dest/c'
    assert_directory 'tmp/cpr_dest/d'
    my_rm_rf 'tmp/cpr_src'
    my_rm_rf 'tmp/cpr_dest'

    bug3588 = '[ruby-core:31360]'
    mkdir 'tmp2'
    assert_nothing_raised(ArgumentError, bug3588) do
      cp_lr 'tmp', 'tmp2'
    end
    assert_directory 'tmp2/tmp'
    assert_raise(ArgumentError, bug3588) do
      cp_lr 'tmp2', 'tmp2/new_tmp2'
    end

    bug12892 = '[ruby-core:77885] [Bug #12892]'
    assert_raise(Errno::ENOENT, bug12892) do
      cp_lr 'non/existent', 'tmp'
    end
  end if have_hardlink?

  def test_mv
    check_singleton :mv

    mkdir 'tmp/dest'
    TARGETS.each do |fname|
      cp fname, 'tmp/mvsrc'
      mv 'tmp/mvsrc', 'tmp/mvdest'
      assert_same_file fname, 'tmp/mvdest'

      mv 'tmp/mvdest', 'tmp/dest/'
      assert_same_file fname, 'tmp/dest/mvdest'

      mv 'tmp/dest/mvdest', 'tmp'
      assert_same_file fname, 'tmp/mvdest'
    end

    mkdir 'tmp/tmpdir'
    mkdir_p 'tmp/dest2/tmpdir'
    assert_raise_with_message(Errno::EEXIST, %r' - tmp/dest2/tmpdir\z',
                              '[ruby-core:68706] [Bug #11021]') {
      mv 'tmp/tmpdir', 'tmp/dest2'
    }
    mkdir 'tmp/dest2/tmpdir/junk'
    assert_raise(Errno::EEXIST, "[ruby-talk:124368]") {
      mv 'tmp/tmpdir', 'tmp/dest2'
    }

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raise(ArgumentError) {
      mv 'tmp/cptmp', 'tmp/cptmp'
    }
  end

  def test_mv_symlink
    touch 'tmp/cptmp'
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raise(ArgumentError) {
      mv 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    assert_raise(ArgumentError) {
      mv 'tmp/cptmp_symlink', 'tmp/cptmp'
    }
  end if have_symlink?

  def test_mv_broken_symlink
    # src==dest (3) looped symlink
    File.symlink 'symlink', 'tmp/symlink'
    assert_raise(Errno::ELOOP) {
      mv 'tmp/symlink', 'tmp/symlink'
    }
    # unexist symlink
    File.symlink 'xxx', 'tmp/src'
    assert_nothing_raised {
      mv 'tmp/src', 'tmp/dest'
    }
    assert_equal true, File.symlink?('tmp/dest')
  end if have_symlink? and !no_broken_symlink?

  def test_mv_pathname
    # pathname
    assert_nothing_raised {
      touch 'tmp/mvtmpsrc'
      mv Pathname.new('tmp/mvtmpsrc'), 'tmp/mvtmpdest'
      touch 'tmp/mvtmpsrc'
      mv 'tmp/mvtmpsrc', Pathname.new('tmp/mvtmpdest')
      touch 'tmp/mvtmpsrc'
      mv Pathname.new('tmp/mvtmpsrc'), Pathname.new('tmp/mvtmpdest')
    }
  end

  def test_rm
    check_singleton :rm

    TARGETS.each do |fname|
      cp fname, 'tmp/rmsrc'
      rm 'tmp/rmsrc'
      assert_file_not_exist 'tmp/rmsrc'
    end

    # pathname
    touch 'tmp/rmtmp1'
    touch 'tmp/rmtmp2'
    touch 'tmp/rmtmp3'
    assert_nothing_raised {
      rm Pathname.new('tmp/rmtmp1')
      rm [Pathname.new('tmp/rmtmp2'), Pathname.new('tmp/rmtmp3')]
    }
    assert_file_not_exist 'tmp/rmtmp1'
    assert_file_not_exist 'tmp/rmtmp2'
    assert_file_not_exist 'tmp/rmtmp3'
  end

  def test_rm_f
    check_singleton :rm_f

    TARGETS.each do |fname|
      cp fname, 'tmp/rmsrc'
      rm_f 'tmp/rmsrc'
      assert_file_not_exist 'tmp/rmsrc'
    end
  end

  def test_rm_symlink
    File.open('tmp/lnf_symlink_src', 'w') {|f| f.puts 'dummy' }
    File.symlink 'lnf_symlink_src', 'tmp/lnf_symlink_dest'
    rm_f 'tmp/lnf_symlink_dest'
    assert_file_not_exist 'tmp/lnf_symlink_dest'
    assert_file_exist     'tmp/lnf_symlink_src'

    rm_f 'notexistdatafile'
    rm_f 'tmp/notexistdatafile'
    my_rm_rf 'tmpdatadir'
    Dir.mkdir 'tmpdatadir'
    # rm_f 'tmpdatadir'
    Dir.rmdir 'tmpdatadir'
  end if have_symlink?

  def test_rm_f_2
    Dir.mkdir 'tmp/tmpdir'
    File.open('tmp/tmpdir/a', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/c', 'w') {|f| f.puts 'dummy' }
    rm_f ['tmp/tmpdir/a', 'tmp/tmpdir/b', 'tmp/tmpdir/c']
    assert_file_not_exist 'tmp/tmpdir/a'
    assert_file_not_exist 'tmp/tmpdir/c'
    Dir.rmdir 'tmp/tmpdir'
  end

  def test_rm_pathname
    # pathname
    touch 'tmp/rmtmp1'
    touch 'tmp/rmtmp2'
    touch 'tmp/rmtmp3'
    touch 'tmp/rmtmp4'
    assert_nothing_raised {
      rm_f Pathname.new('tmp/rmtmp1')
      rm_f [Pathname.new('tmp/rmtmp2'), Pathname.new('tmp/rmtmp3')]
    }
    assert_file_not_exist 'tmp/rmtmp1'
    assert_file_not_exist 'tmp/rmtmp2'
    assert_file_not_exist 'tmp/rmtmp3'
    assert_file_exist 'tmp/rmtmp4'

    # [ruby-dev:39345]
    touch 'tmp/[rmtmp]'
    FileUtils.rm_f 'tmp/[rmtmp]'
    assert_file_not_exist 'tmp/[rmtmp]'
  end

  def test_rm_r
    check_singleton :rm_r

    my_rm_rf 'tmpdatadir'

    Dir.mkdir 'tmpdatadir'
    rm_r 'tmpdatadir'
    assert_file_not_exist 'tmpdatadir'

    Dir.mkdir 'tmpdatadir'
    rm_r 'tmpdatadir/'
    assert_file_not_exist 'tmpdatadir'

    Dir.mkdir 'tmp/tmpdir'
    rm_r 'tmp/tmpdir/'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'

    Dir.mkdir 'tmp/tmpdir'
    rm_r 'tmp/tmpdir'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'

    Dir.mkdir 'tmp/tmpdir'
    File.open('tmp/tmpdir/a', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/b', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/c', 'w') {|f| f.puts 'dummy' }
    rm_r 'tmp/tmpdir'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'

    Dir.mkdir 'tmp/tmpdir'
    File.open('tmp/tmpdir/a', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/c', 'w') {|f| f.puts 'dummy' }
    rm_r ['tmp/tmpdir/a', 'tmp/tmpdir/b', 'tmp/tmpdir/c'], :force => true
    assert_file_not_exist 'tmp/tmpdir/a'
    assert_file_not_exist 'tmp/tmpdir/c'
    Dir.rmdir 'tmp/tmpdir'
  end

  def test_rm_r_symlink
    # [ruby-talk:94635] a symlink to the directory
    Dir.mkdir 'tmp/tmpdir'
    File.symlink '..', 'tmp/tmpdir/symlink_to_dir'
    rm_r 'tmp/tmpdir'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'
  end if have_symlink?

  def test_rm_r_pathname
    # pathname
    Dir.mkdir 'tmp/tmpdir1'; touch 'tmp/tmpdir1/tmp'
    Dir.mkdir 'tmp/tmpdir2'; touch 'tmp/tmpdir2/tmp'
    Dir.mkdir 'tmp/tmpdir3'; touch 'tmp/tmpdir3/tmp'
    assert_nothing_raised {
      rm_r Pathname.new('tmp/tmpdir1')
      rm_r [Pathname.new('tmp/tmpdir2'), Pathname.new('tmp/tmpdir3')]
    }
    assert_file_not_exist 'tmp/tmpdir1'
    assert_file_not_exist 'tmp/tmpdir2'
    assert_file_not_exist 'tmp/tmpdir3'
  end

  def test_rm_r_no_permissions
    check_singleton :rm_rf

    return if /mswin|mingw/ =~ RUBY_PLATFORM

    mkdir 'tmpdatadir'
    touch 'tmpdatadir/tmpdata'
    chmod "-x", 'tmpdatadir'

    begin
      assert_raise Errno::EACCES do
        rm_r 'tmpdatadir'
      end
    ensure
      chmod "+x", 'tmpdatadir'
    end
  end

  def test_remove_entry_cjk_path
    dir = "tmpdir\u3042"
    my_rm_rf dir

    Dir.mkdir dir
    File.write("#{dir}/\u3042.txt", "test_remove_entry_cjk_path")

    remove_entry dir
    assert_file_not_exist dir
  end

  def test_remove_entry_multibyte_path
    c = "\u00a7"
    begin
      c = c.encode('filesystem')
    rescue EncodingError
      c = c.b
    end
    dir = "tmpdir#{c}"
    my_rm_rf dir

    Dir.mkdir dir
    File.write("#{dir}/#{c}.txt", "test_remove_entry_multibyte_path")

    remove_entry dir
    assert_file_not_exist dir
  end

  def test_remove_entry_secure
    check_singleton :remove_entry_secure

    my_rm_rf 'tmpdatadir'

    Dir.mkdir 'tmpdatadir'
    remove_entry_secure 'tmpdatadir'
    assert_file_not_exist 'tmpdatadir'

    Dir.mkdir 'tmpdatadir'
    remove_entry_secure 'tmpdatadir/'
    assert_file_not_exist 'tmpdatadir'

    Dir.mkdir 'tmp/tmpdir'
    remove_entry_secure 'tmp/tmpdir/'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'

    Dir.mkdir 'tmp/tmpdir'
    remove_entry_secure 'tmp/tmpdir'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'

    Dir.mkdir 'tmp/tmpdir'
    File.open('tmp/tmpdir/a', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/b', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/c', 'w') {|f| f.puts 'dummy' }
    remove_entry_secure 'tmp/tmpdir'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'

    Dir.mkdir 'tmp/tmpdir'
    File.open('tmp/tmpdir/a', 'w') {|f| f.puts 'dummy' }
    File.open('tmp/tmpdir/c', 'w') {|f| f.puts 'dummy' }
    remove_entry_secure 'tmp/tmpdir/a', true
    remove_entry_secure 'tmp/tmpdir/b', true
    remove_entry_secure 'tmp/tmpdir/c', true
    assert_file_not_exist 'tmp/tmpdir/a'
    assert_file_not_exist 'tmp/tmpdir/c'

    unless root_in_posix?
      File.chmod(01777, 'tmp/tmpdir')
      if File.sticky?('tmp/tmpdir')
        Dir.mkdir 'tmp/tmpdir/d', 0
        assert_raise(Errno::EACCES) {remove_entry_secure 'tmp/tmpdir/d'}
        File.chmod 0o777, 'tmp/tmpdir/d'
        Dir.rmdir 'tmp/tmpdir/d'
      end
    end

    Dir.rmdir 'tmp/tmpdir'
  end

  def test_remove_entry_secure_symlink
    # [ruby-talk:94635] a symlink to the directory
    Dir.mkdir 'tmp/tmpdir'
    File.symlink '..', 'tmp/tmpdir/symlink_to_dir'
    remove_entry_secure 'tmp/tmpdir'
    assert_file_not_exist 'tmp/tmpdir'
    assert_file_exist     'tmp'
  end if have_symlink?

  def test_remove_entry_secure_pathname
    # pathname
    Dir.mkdir 'tmp/tmpdir1'; touch 'tmp/tmpdir1/tmp'
    assert_nothing_raised {
      remove_entry_secure Pathname.new('tmp/tmpdir1')
    }
    assert_file_not_exist 'tmp/tmpdir1'
  end

  def test_with_big_file
    prepare_big_file

    cp BIGFILE, 'tmp/cpdest'
    assert_same_file BIGFILE, 'tmp/cpdest'
    assert cmp(BIGFILE, 'tmp/cpdest'), 'orig != copied'

    mv 'tmp/cpdest', 'tmp/mvdest'
    assert_same_file BIGFILE, 'tmp/mvdest'
    assert_file_not_exist 'tmp/cpdest'

    rm 'tmp/mvdest'
    assert_file_not_exist 'tmp/mvdest'
  end

  def test_ln
    TARGETS.each do |fname|
      ln fname, 'tmp/lndest'
      assert_same_file fname, 'tmp/lndest'
      File.unlink 'tmp/lndest'
    end

    ln TARGETS, 'tmp'
    TARGETS.each do |fname|
      assert_same_file fname, 'tmp/' + File.basename(fname)
    end
    TARGETS.each do |fname|
      File.unlink 'tmp/' + File.basename(fname)
    end

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raise(Errno::EEXIST) {
      ln 'tmp/cptmp', 'tmp/cptmp'
    }
  end if have_hardlink?

  def test_ln_symlink
    touch 'tmp/cptmp'
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/symlink'
    assert_raise(Errno::EEXIST) {
      ln 'tmp/cptmp', 'tmp/symlink'   # normal file -> symlink
    }
    assert_raise(Errno::EEXIST) {
      ln 'tmp/symlink', 'tmp/cptmp'   # symlink -> normal file
    }
  end if have_symlink?

  def test_ln_broken_symlink
    # src==dest (3) looped symlink
    File.symlink 'cptmp_symlink', 'tmp/cptmp_symlink'
    begin
      ln 'tmp/cptmp_symlink', 'tmp/cptmp_symlink'
    rescue => err
      assert_kind_of SystemCallError, err
    end
  end if have_symlink? and !no_broken_symlink?

  def test_ln_pathname
    # pathname
    touch 'tmp/lntmp'
    assert_nothing_raised {
      ln Pathname.new('tmp/lntmp'), 'tmp/lndesttmp1'
      ln 'tmp/lntmp', Pathname.new('tmp/lndesttmp2')
      ln Pathname.new('tmp/lntmp'), Pathname.new('tmp/lndesttmp3')
    }
  end if have_hardlink?

  def test_ln_s
    check_singleton :ln_s

    ln_s TARGETS, 'tmp'
    each_srcdest do |fname, lnfname|
      assert_equal fname, File.readlink(lnfname)
    ensure
      rm_f lnfname
    end

    lnfname = 'symlink'
    assert_raise(Errno::ENOENT, "multiple targets need a destination directory") {
      ln_s TARGETS, lnfname
    }
    assert_file.not_exist?(lnfname)

    TARGETS.each do |fname|
      fname = "../#{fname}"
      lnfname = 'tmp/lnsdest'
      ln_s fname, lnfname
      assert_file.symlink?(lnfname)
      assert_equal fname, File.readlink(lnfname)
    ensure
      rm_f lnfname
    end
  end if have_symlink? and !no_broken_symlink?

  def test_ln_s_broken_symlink
    assert_nothing_raised {
      ln_s 'symlink', 'tmp/symlink'
    }
    assert_symlink 'tmp/symlink'
  end if have_symlink? and !no_broken_symlink?

  def test_ln_s_pathname
    # pathname
    touch 'tmp/lnsdest'
    assert_nothing_raised {
      ln_s Pathname.new('lnsdest'), 'tmp/symlink_tmp1'
      ln_s 'lnsdest', Pathname.new('tmp/symlink_tmp2')
      ln_s Pathname.new('lnsdest'), Pathname.new('tmp/symlink_tmp3')
    }
  end if have_symlink?

  def test_ln_sf
    check_singleton :ln_sf

    TARGETS.each do |fname|
      fname = "../#{fname}"
      ln_sf fname, 'tmp/lnsdest'
      assert FileTest.symlink?('tmp/lnsdest'), 'not symlink'
      assert_equal fname, File.readlink('tmp/lnsdest')
      ln_sf fname, 'tmp/lnsdest'
      ln_sf fname, 'tmp/lnsdest'
    end
  end if have_symlink?

  def test_ln_sf_broken_symlink
    assert_nothing_raised {
      ln_sf 'symlink', 'tmp/symlink'
    }
  end if have_symlink? and !no_broken_symlink?

  def test_ln_sf_pathname
    # pathname
    touch 'tmp/lns_dest'
    assert_nothing_raised {
      ln_sf Pathname.new('lns_dest'), 'tmp/symlink_tmp1'
      ln_sf 'lns_dest', Pathname.new('tmp/symlink_tmp2')
      ln_sf Pathname.new('lns_dest'), Pathname.new('tmp/symlink_tmp3')
    }
  end if have_symlink?

  def test_ln_sr
    check_singleton :ln_sr

    assert_all_assertions_foreach(nil, *TARGETS) do |fname|
      lnfname = 'tmp/lnsdest'
      ln_sr fname, lnfname
      assert_file.symlink?(lnfname)
      assert_file.identical?(lnfname, fname)
      assert_equal "../#{fname}", File.readlink(lnfname)
    ensure
      rm_f lnfname
    end

    ln_sr TARGETS, 'tmp'
    assert_all_assertions do |all|
      each_srcdest do |fname, lnfname|
        all.for(fname) do
          assert_equal "../#{fname}", File.readlink(lnfname)
        end
      ensure
        rm_f lnfname
      end
    end

    File.symlink 'data', 'link'
    mkdir 'link/d1'
    mkdir 'link/d2'
    ln_sr 'link/d1/z', 'link/d2'
    assert_equal '../d1/z', File.readlink('data/d2/z')

    mkdir 'data/src'
    File.write('data/src/xxx', 'ok')
    File.symlink '../data/src', 'tmp/src'
    ln_sr 'tmp/src/xxx', 'data'
    assert_file.symlink?('data/xxx')
    assert_equal 'ok', File.read('data/xxx')
    assert_equal 'src/xxx', File.readlink('data/xxx')
  end

  def test_ln_sr_not_target_directory
    assert_raise(ArgumentError) {
      ln_sr TARGETS, 'tmp', target_directory: false
    }
    assert_empty(Dir.children('tmp'))

    lnfname = 'symlink'
    assert_raise(ArgumentError) {
      ln_sr TARGETS, lnfname, target_directory: false
    }
    assert_file.not_exist?(lnfname)

    assert_all_assertions_foreach(nil, *TARGETS) do |fname|
      assert_raise(Errno::EEXIST, Errno::EACCES) {
        ln_sr fname, 'tmp', target_directory: false
      }
      assert_file.not_exist? File.join('tmp/', File.basename(fname))
    end
  end if have_symlink?

  def test_ln_sr_broken_symlink
    assert_nothing_raised {
      ln_sr 'tmp/symlink', 'tmp/symlink'
    }
  end if have_symlink? and !no_broken_symlink?

  def test_ln_sr_pathname
    # pathname
    touch 'tmp/lns_dest'
    assert_nothing_raised {
      ln_sr Pathname.new('tmp/lns_dest'), 'tmp/symlink_tmp1'
      ln_sr 'tmp/lns_dest', Pathname.new('tmp/symlink_tmp2')
      ln_sr Pathname.new('tmp/lns_dest'), Pathname.new('tmp/symlink_tmp3')
    }
  end if have_symlink?

  def test_mkdir
    check_singleton :mkdir

    my_rm_rf 'tmpdatadir'
    mkdir 'tmpdatadir'
    assert_directory 'tmpdatadir'
    Dir.rmdir 'tmpdatadir'

    mkdir 'tmpdatadir/'
    assert_directory 'tmpdatadir'
    Dir.rmdir 'tmpdatadir'

    mkdir 'tmp/mkdirdest'
    assert_directory 'tmp/mkdirdest'
    Dir.rmdir 'tmp/mkdirdest'

    mkdir 'tmp/tmp', :mode => 0700
    assert_directory 'tmp/tmp'
    assert_filemode 0700, 'tmp/tmp', mask: 0777 if have_file_perm?
    Dir.rmdir 'tmp/tmp'

    # EISDIR on OS X, FreeBSD; EEXIST on Linux; Errno::EACCES on Windows
    assert_raise(Errno::EISDIR, Errno::EEXIST, Errno::EACCES) {
      mkdir '/'
    }
  end

  def test_mkdir_file_perm
    mkdir 'tmp/tmp', :mode => 07777
    assert_directory 'tmp/tmp'
    assert_filemode 07777, 'tmp/tmp'
    Dir.rmdir 'tmp/tmp'
  end if have_file_perm?

  def test_mkdir_lf_in_path
    mkdir "tmp-first-line\ntmp-second-line"
    assert_directory "tmp-first-line\ntmp-second-line"
    Dir.rmdir "tmp-first-line\ntmp-second-line"
  end if lf_in_path_allowed?

  def test_mkdir_pathname
    # pathname
    assert_nothing_raised {
      mkdir Pathname.new('tmp/tmpdirtmp')
      mkdir [Pathname.new('tmp/tmpdirtmp2'), Pathname.new('tmp/tmpdirtmp3')]
    }
  end

  def test_mkdir_p
    check_singleton :mkdir_p

    dirs = %w(
      tmpdir/dir/
      tmpdir/dir/./
      tmpdir/dir/./.././dir/
      tmpdir/a
      tmpdir/a/
      tmpdir/a/b
      tmpdir/a/b/
      tmpdir/a/b/c/
      tmpdir/a/b/c
      tmpdir/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a
      tmpdir/a/a
    )
    my_rm_rf 'tmpdir'
    dirs.each do |d|
      mkdir_p d
      assert_directory d
      assert_file_not_exist "#{d}/a"
      assert_file_not_exist "#{d}/b"
      assert_file_not_exist "#{d}/c"
      my_rm_rf 'tmpdir'
    end
    dirs.each do |d|
      mkdir_p d
      assert_directory d
    end
    rm_rf 'tmpdir'
    dirs.each do |d|
      mkdir_p "#{Dir.pwd}/#{d}"
      assert_directory d
    end
    rm_rf 'tmpdir'

    mkdir_p 'tmp/tmp/tmp', :mode => 0700
    assert_directory 'tmp/tmp'
    assert_directory 'tmp/tmp/tmp'
    assert_filemode 0700, 'tmp/tmp', mask: 0777 if have_file_perm?
    assert_filemode 0700, 'tmp/tmp/tmp', mask: 0777 if have_file_perm?
    rm_rf 'tmp/tmp'

    mkdir_p 'tmp/tmp', :mode => 0
    assert_directory 'tmp/tmp'
    assert_filemode 0, 'tmp/tmp', mask: 0777 if have_file_perm?
    # DO NOT USE rm_rf here.
    # (rm(1) try to chdir to parent directory, it fails to remove directory.)
    Dir.rmdir 'tmp/tmp'
    Dir.rmdir 'tmp'

    mkdir_p '/'
  end

  if /mswin|mingw|cygwin/ =~ RUBY_PLATFORM
    def test_mkdir_p_root
      if /cygwin/ =~ RUBY_PLATFORM
        tmpdir = `cygpath -ma .`.chomp
      else
        tmpdir = Dir.pwd
      end
      pend "No drive letter" unless /\A[a-z]:/i =~ tmpdir
      drive = "./#{$&}"
      assert_file_not_exist drive
      mkdir_p "#{tmpdir}/none/dir"
      assert_directory "none/dir"
      assert_file_not_exist drive
    ensure
      Dir.rmdir(drive) if drive and File.directory?(drive)
    end

    def test_mkdir_p_offline_drive
      offline_drive = ("A".."Z").to_a.reverse.find {|d| !File.exist?("#{d}:/") }

      assert_raise(Errno::ENOENT) {
        mkdir_p "#{offline_drive}:/new_dir"
      }
    end
  end

  def test_mkdir_p_file_perm
    mkdir_p 'tmp/tmp/tmp', :mode => 07777
    assert_directory 'tmp/tmp/tmp'
    assert_filemode 07777, 'tmp/tmp/tmp'
    Dir.rmdir 'tmp/tmp/tmp'
    Dir.rmdir 'tmp/tmp'
  end if have_file_perm?

  def test_mkdir_p_pathname
    # pathname
    assert_nothing_raised {
      mkdir_p Pathname.new('tmp/tmp/tmp')
    }
  end

  def test_install
    check_singleton :install

    File.open('tmp/aaa', 'w') {|f| f.puts 'aaa' }
    File.open('tmp/bbb', 'w') {|f| f.puts 'bbb' }
    install 'tmp/aaa', 'tmp/bbb', :mode => 0600
    assert_equal "aaa\n", File.read('tmp/bbb')
    assert_filemode 0600, 'tmp/bbb', mask: 0777 if have_file_perm?

    t = File.mtime('tmp/bbb')
    install 'tmp/aaa', 'tmp/bbb'
    assert_equal "aaa\n", File.read('tmp/bbb')
    assert_filemode 0600, 'tmp/bbb', mask: 0777 if have_file_perm?
    assert_equal_time t, File.mtime('tmp/bbb')

    File.unlink 'tmp/aaa'
    File.unlink 'tmp/bbb'

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raise(ArgumentError) {
      install 'tmp/cptmp', 'tmp/cptmp'
    }
  end

  def test_install_symlink
    touch 'tmp/cptmp'
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raise(ArgumentError) {
      install 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    assert_raise(ArgumentError) {
      install 'tmp/cptmp_symlink', 'tmp/cptmp'
    }
  end if have_symlink?

  def test_install_broken_symlink
    # src==dest (3) looped symlink
    File.symlink 'symlink', 'tmp/symlink'
    assert_raise(Errno::ELOOP) {
      # File#install invokes open(2), always ELOOP must be raised
      install 'tmp/symlink', 'tmp/symlink'
    }
  end if have_symlink? and !no_broken_symlink?

  def test_install_pathname
    # pathname
    assert_nothing_raised {
      rm_f 'tmp/a'; touch 'tmp/a'
      install 'tmp/a', Pathname.new('tmp/b')
      rm_f 'tmp/a'; touch 'tmp/a'
      install Pathname.new('tmp/a'), 'tmp/b'
      rm_f 'tmp/a'; touch 'tmp/a'
      install Pathname.new('tmp/a'), Pathname.new('tmp/b')
      my_rm_rf 'tmp/new_dir_end_with_slash'
      install Pathname.new('tmp/a'), 'tmp/new_dir_end_with_slash/'
      my_rm_rf 'tmp/new_dir_end_with_slash'
      my_rm_rf 'tmp/new_dir'
      install Pathname.new('tmp/a'), 'tmp/new_dir/a'
      my_rm_rf 'tmp/new_dir'
      install Pathname.new('tmp/a'), 'tmp/new_dir/new_dir_end_with_slash/'
      my_rm_rf 'tmp/new_dir'
      rm_f 'tmp/a'
      touch 'tmp/a'
      touch 'tmp/b'
      mkdir 'tmp/dest'
      install [Pathname.new('tmp/a'), Pathname.new('tmp/b')], 'tmp/dest'
      my_rm_rf 'tmp/dest'
      mkdir 'tmp/dest'
      install [Pathname.new('tmp/a'), Pathname.new('tmp/b')], Pathname.new('tmp/dest')
    }
  end

  def test_install_owner_option
    File.open('tmp/aaa', 'w') {|f| f.puts 'aaa' }
    File.open('tmp/bbb', 'w') {|f| f.puts 'bbb' }
    assert_nothing_raised {
      install 'tmp/aaa', 'tmp/bbb', :owner => "nobody", :noop => true
    }
  end

  def test_install_group_option
    File.open('tmp/aaa', 'w') {|f| f.puts 'aaa' }
    File.open('tmp/bbb', 'w') {|f| f.puts 'bbb' }
    assert_nothing_raised {
      install 'tmp/aaa', 'tmp/bbb', :group => "nobody", :noop => true
    }
  end

  def test_install_mode_option
    File.open('tmp/a', 'w') {|f| f.puts 'aaa' }
    install 'tmp/a', 'tmp/b', :mode => "u=wrx,g=rx,o=x"
    assert_filemode 0751, 'tmp/b'
    install 'tmp/b', 'tmp/c', :mode => "g+w-x"
    assert_filemode 0761, 'tmp/c'
    install 'tmp/c', 'tmp/d', :mode => "o+r,g=o+w,o-r,u-o" # 761 => 763 => 773 => 771 => 671
    assert_filemode 0671, 'tmp/d'
    install 'tmp/d', 'tmp/e', :mode => "go=u"
    assert_filemode 0666, 'tmp/e'
    install 'tmp/e', 'tmp/f', :mode => "u=wrx,g=,o="
    assert_filemode 0700, 'tmp/f'
    install 'tmp/f', 'tmp/g', :mode => "u=rx,go="
    assert_filemode 0500, 'tmp/g'
    install 'tmp/g', 'tmp/h', :mode => "+wrx"
    assert_filemode 0777, 'tmp/h'
    install 'tmp/h', 'tmp/i', :mode => "u+s,o=s"
    assert_filemode 04770, 'tmp/i'
    install 'tmp/i', 'tmp/j', :mode => "u-w,go-wrx"
    assert_filemode 04500, 'tmp/j'
    install 'tmp/j', 'tmp/k', :mode => "+s"
    assert_filemode 06500, 'tmp/k'
    install 'tmp/a', 'tmp/l', :mode => "o+X"
    assert_equal_filemode 'tmp/a', 'tmp/l'
  end if have_file_perm?

  def test_chmod
    check_singleton :chmod

    touch 'tmp/a'
    chmod 0o700, 'tmp/a'
    assert_filemode 0700, 'tmp/a'
    chmod 0o500, 'tmp/a'
    assert_filemode 0500, 'tmp/a'
  end if have_file_perm?

  def test_chmod_symbol_mode
    check_singleton :chmod

    touch 'tmp/a'
    chmod "u=wrx,g=rx,o=x", 'tmp/a'
    assert_filemode 0751, 'tmp/a'
    chmod "g+w-x", 'tmp/a'
    assert_filemode 0761, 'tmp/a'
    chmod "o+r,g=o+w,o-r,u-o", 'tmp/a' # 761 => 763 => 773 => 771 => 671
    assert_filemode 0671, 'tmp/a'
    chmod "go=u", 'tmp/a'
    assert_filemode 0666, 'tmp/a'
    chmod "u=wrx,g=,o=", 'tmp/a'
    assert_filemode 0700, 'tmp/a'
    chmod "u=rx,go=", 'tmp/a'
    assert_filemode 0500, 'tmp/a'
    chmod "+wrx", 'tmp/a'
    assert_filemode 0777, 'tmp/a'
    chmod "u+s,o=s", 'tmp/a'
    assert_filemode 04770, 'tmp/a'
    chmod "u-w,go-wrx", 'tmp/a'
    assert_filemode 04500, 'tmp/a'
    chmod "+s", 'tmp/a'
    assert_filemode 06500, 'tmp/a'

    # FreeBSD ufs and tmpfs don't allow to change sticky bit against
    # regular file. It's slightly strange. Anyway it's no effect bit.
    # see /usr/src/sys/ufs/ufs/ufs_chmod()
    # NetBSD, OpenBSD, Solaris, and AIX also deny it.
    if /freebsd|netbsd|openbsd|aix/ !~ RUBY_PLATFORM
      chmod "u+t,o+t", 'tmp/a'
      assert_filemode 07500, 'tmp/a'
      chmod "a-t,a-s", 'tmp/a'
      assert_filemode 0500, 'tmp/a'
    end

    assert_raise_with_message(ArgumentError, /invalid\b.*\bfile mode/) {
      chmod "a", 'tmp/a'
    }

    assert_raise_with_message(ArgumentError, /invalid\b.*\bfile mode/) {
      chmod "x+a", 'tmp/a'
    }

    assert_raise_with_message(ArgumentError, /invalid\b.*\bfile mode/) {
      chmod "u+z", 'tmp/a'
    }

    assert_raise_with_message(ArgumentError, /invalid\b.*\bfile mode/) {
      chmod ",+x", 'tmp/a'
    }

    assert_raise_with_message(ArgumentError, /invalid\b.*\bfile mode/) {
      chmod "755", 'tmp/a'
    }

  end if have_file_perm?


  def test_chmod_R
    check_singleton :chmod_R

    mkdir_p 'tmp/dir/dir'
    touch %w( tmp/dir/file tmp/dir/dir/file )
    chmod_R 0700, 'tmp/dir'
    assert_filemode 0700, 'tmp/dir', mask: 0777
    assert_filemode 0700, 'tmp/dir/file', mask: 0777
    assert_filemode 0700, 'tmp/dir/dir', mask: 0777
    assert_filemode 0700, 'tmp/dir/dir/file', mask: 0777
    chmod_R 0500, 'tmp/dir'
    assert_filemode 0500, 'tmp/dir', mask: 0777
    assert_filemode 0500, 'tmp/dir/file', mask: 0777
    assert_filemode 0500, 'tmp/dir/dir', mask: 0777
    assert_filemode 0500, 'tmp/dir/dir/file', mask: 0777
    chmod_R 0700, 'tmp/dir'   # to remove
  end if have_file_perm?

  def test_chmod_symbol_mode_R
    check_singleton :chmod_R

    mkdir_p 'tmp/dir/dir'
    touch %w( tmp/dir/file tmp/dir/dir/file )
    chmod_R "u=wrx,g=,o=", 'tmp/dir'
    assert_filemode 0700, 'tmp/dir', mask: 0777
    assert_filemode 0700, 'tmp/dir/file', mask: 0777
    assert_filemode 0700, 'tmp/dir/dir', mask: 0777
    assert_filemode 0700, 'tmp/dir/dir/file', mask: 0777
    chmod_R "u=xr,g+X,o=", 'tmp/dir'
    assert_filemode 0510, 'tmp/dir', mask: 0777
    assert_filemode 0500, 'tmp/dir/file', mask: 0777
    assert_filemode 0510, 'tmp/dir/dir', mask: 0777
    assert_filemode 0500, 'tmp/dir/dir/file', mask: 0777
    chmod_R 0700, 'tmp/dir'   # to remove
  end if have_file_perm?

  def test_chmod_verbose
    check_singleton :chmod

    assert_output_lines(["chmod 700 tmp/a", "chmod 500 tmp/a"]) {
      touch 'tmp/a'
      chmod 0o700, 'tmp/a', verbose: true
      assert_filemode 0700, 'tmp/a', mask: 0777
      chmod 0o500, 'tmp/a', verbose: true
      assert_filemode 0500, 'tmp/a', mask: 0777
    }
  end if have_file_perm?

  def test_s_chmod_verbose
    assert_output_lines(["chmod 700 tmp/a"], FileUtils) {
      touch 'tmp/a'
      FileUtils.chmod 0o700, 'tmp/a', verbose: true
      assert_filemode 0700, 'tmp/a', mask: 0777
    }
  end if have_file_perm?

  def test_chown
    check_singleton :chown

    return unless @groups[1]

    input_group_1 = @groups[0]
    assert_output_lines([]) {
      touch 'tmp/a'
      # integer input for group, nil for user
      chown nil, input_group_1, 'tmp/a'
      assert_ownership_group @groups[0], 'tmp/a'
    }

    input_group_2 = Etc.getgrgid(@groups[1]).name
    assert_output_lines([]) {
      touch 'tmp/b'
      # string input for group, -1 for user
      chown(-1, input_group_2, 'tmp/b')
      assert_ownership_group @groups[1], 'tmp/b'
    }
  end if have_file_perm?

  def test_chown_verbose
    assert_output_lines(["chown :#{@groups[0]} tmp/a1 tmp/a2"]) {
      touch 'tmp/a1'
      touch 'tmp/a2'
      chown nil, @groups[0], ['tmp/a1', 'tmp/a2'], verbose: true
      assert_ownership_group @groups[0], 'tmp/a1'
      assert_ownership_group @groups[0], 'tmp/a2'
    }
  end if have_file_perm?

  def test_chown_noop
    return unless @groups[1]
    assert_output_lines([]) {
      touch 'tmp/a'
      chown nil, @groups[0], 'tmp/a', :noop => false
      assert_ownership_group @groups[0], 'tmp/a'
      chown nil, @groups[1], 'tmp/a', :noop => true
      assert_ownership_group @groups[0], 'tmp/a'
      chown nil, @groups[1], 'tmp/a'
      assert_ownership_group @groups[1], 'tmp/a'
    }
  end if have_file_perm?

  if have_file_perm?
    def test_chown_error
      uid = UID_1
      return unless uid

      touch 'tmp/a'

      # getpwnam("") on Mac OS X doesn't err.
      # passwd & group databases format is colon-separated, so user &
      # group name can't contain a colon.

      assert_raise_with_message(ArgumentError, "can't find user for :::") {
        chown ":::", @groups[0], 'tmp/a'
      }

      assert_raise_with_message(ArgumentError, "can't find group for :::") {
        chown uid, ":::", 'tmp/a'
      }

      assert_raise_with_message(Errno::ENOENT, /No such file or directory/) {
        chown nil, @groups[0], ''
      }
    end

    def test_chown_dir_group_ownership_not_recursive
      return unless @groups[1]

      input_group_1 = @groups[0]
      input_group_2 = @groups[1]
      assert_output_lines([]) {
        mkdir 'tmp/dir'
        touch 'tmp/dir/a'
        chown nil, input_group_1, ['tmp/dir', 'tmp/dir/a']
        assert_ownership_group @groups[0], 'tmp/dir'
        assert_ownership_group @groups[0], 'tmp/dir/a'
        chown nil, input_group_2, 'tmp/dir'
        assert_ownership_group @groups[1], 'tmp/dir'
        # Make sure FileUtils.chown does not chown recursively
        assert_ownership_group @groups[0], 'tmp/dir/a'
      }
    end

    def test_chown_R
      check_singleton :chown_R

      return unless @groups[1]

      input_group_1 = @groups[0]
      input_group_2 = @groups[1]
      assert_output_lines([]) {
        list = ['tmp/dir', 'tmp/dir/a', 'tmp/dir/a/b', 'tmp/dir/a/b/c']
        mkdir_p 'tmp/dir/a/b/c'
        touch 'tmp/d'
        # string input
        chown_R nil, input_group_1, 'tmp/dir'
        list.each {|dir|
          assert_ownership_group @groups[0], dir
        }
        chown_R nil, input_group_1, 'tmp/d'
        assert_ownership_group @groups[0], 'tmp/d'
        # list input
        chown_R nil, input_group_2, ['tmp/dir', 'tmp/d']
        list += ['tmp/d']
        list.each {|dir|
          assert_ownership_group @groups[1], dir
        }
      }
    end

    def test_chown_R_verbose
      assert_output_lines(["chown -R :#{@groups[0]} tmp/dir tmp/d"]) {
        list = ['tmp/dir', 'tmp/dir/a', 'tmp/dir/a/b', 'tmp/dir/a/b/c']
        mkdir_p 'tmp/dir/a/b/c'
        touch 'tmp/d'
        chown_R nil, @groups[0], ['tmp/dir', 'tmp/d'], :verbose => true
        list.each {|dir|
          assert_ownership_group @groups[0], dir
        }
      }
    end

    def test_chown_R_noop
      return unless @groups[1]

      assert_output_lines([]) {
        list = ['tmp/dir', 'tmp/dir/a', 'tmp/dir/a/b', 'tmp/dir/a/b/c']
        mkdir_p 'tmp/dir/a/b/c'
        chown_R nil, @groups[0], 'tmp/dir', :noop => false
        list.each {|dir|
          assert_ownership_group @groups[0], dir
        }
        chown_R nil, @groups[1], 'tmp/dir', :noop => true
        list.each {|dir|
          assert_ownership_group @groups[0], dir
        }
      }
    end

    def test_chown_R_force
      assert_output_lines([]) {
        list = ['tmp/dir', 'tmp/dir/a', 'tmp/dir/a/b', 'tmp/dir/a/b/c']
        mkdir_p 'tmp/dir/a/b/c'
        assert_raise_with_message(Errno::ENOENT, /No such file or directory/) {
            chown_R nil, @groups[0], ['tmp/dir', 'invalid'], :force => false
        }
        chown_R nil, @groups[0], ['tmp/dir', 'invalid'], :force => true
        list.each {|dir|
          assert_ownership_group @groups[0], dir
        }
      }
    end

    if root_in_posix?
      def test_chown_with_root
        gid = @groups[0] # Most of the time, root only has one group

        files = ['tmp/a1', 'tmp/a2']
        files.each {|file| touch file}
        [UID_1, UID_2].each {|uid|
          assert_output_lines(["chown #{uid}:#{gid} tmp/a1 tmp/a2"]) {
            chown uid, gid, files, verbose: true
            files.each {|file|
              assert_ownership_group gid, file
              assert_ownership_user uid, file
            }
          }
        }
      end

      def test_chown_dir_user_ownership_not_recursive_with_root
        assert_output_lines([]) {
          mkdir 'tmp/dir'
          touch 'tmp/dir/a'
          chown UID_1, nil, ['tmp/dir', 'tmp/dir/a']
          assert_ownership_user UID_1, 'tmp/dir'
          assert_ownership_user UID_1, 'tmp/dir/a'
          chown UID_2, nil, 'tmp/dir'
          assert_ownership_user UID_2, 'tmp/dir'
          # Make sure FileUtils.chown does not chown recursively
          assert_ownership_user UID_1, 'tmp/dir/a'
        }
      end

      def test_chown_R_with_root
        assert_output_lines([]) {
          list = ['tmp/dir', 'tmp/dir/a', 'tmp/dir/a/b', 'tmp/dir/a/b/c']
          mkdir_p 'tmp/dir/a/b/c'
          touch 'tmp/d'
          # string input
          chown_R UID_1, nil, 'tmp/dir'
          list.each {|dir|
            assert_ownership_user UID_1, dir
          }
          chown_R UID_1, nil, 'tmp/d'
          assert_ownership_user UID_1, 'tmp/d'
          # list input
          chown_R UID_2, nil, ['tmp/dir', 'tmp/d']
          list += ['tmp/d']
          list.each {|dir|
            assert_ownership_user UID_2, dir
          }
        }
      end
    else
      def test_chown_without_permission
        touch 'tmp/a'
        assert_raise(Errno::EPERM) {
          chown UID_1, nil, 'tmp/a'
          chown UID_2, nil, 'tmp/a'
        }
      end

      def test_chown_R_without_permission
        touch 'tmp/a'
        assert_raise(Errno::EPERM) {
          chown_R UID_1, nil, 'tmp/a'
          chown_R UID_2, nil, 'tmp/a'
        }
      end
    end
  end if UID_1 and UID_2

  def test_copy_entry
    check_singleton :copy_entry

    each_srcdest do |srcpath, destpath|
      copy_entry srcpath, destpath
      assert_same_file srcpath, destpath
      assert_equal File.stat(srcpath).ftype, File.stat(destpath).ftype
    end
  end

  def test_copy_entry_symlink
    # root is a symlink
    touch 'tmp/somewhere'
    File.symlink 'somewhere', 'tmp/symsrc'
    copy_entry 'tmp/symsrc', 'tmp/symdest'
    assert_symlink 'tmp/symdest'
    assert_equal 'somewhere', File.readlink('tmp/symdest')

    # content is a symlink
    mkdir 'tmp/dir'
    touch 'tmp/dir/somewhere'
    File.symlink 'somewhere', 'tmp/dir/sym'
    copy_entry 'tmp/dir', 'tmp/dirdest'
    assert_directory 'tmp/dirdest'
    assert_not_symlink 'tmp/dirdest'
    assert_symlink 'tmp/dirdest/sym'
    assert_equal 'somewhere', File.readlink('tmp/dirdest/sym')
  end if have_symlink?

  def test_copy_entry_symlink_remove_destination
    Dir.mkdir 'tmp/dir'
    File.symlink 'tmp/dir', 'tmp/dest'
    touch 'tmp/src'
    copy_entry 'tmp/src', 'tmp/dest', false, false, true
    assert_file_exist 'tmp/dest'
  end if have_symlink?

  def test_copy_file
    check_singleton :copy_file

    each_srcdest do |srcpath, destpath|
      copy_file srcpath, destpath
      assert_same_file srcpath, destpath
    end
  end

  def test_copy_stream
    check_singleton :copy_stream
    # IO
    each_srcdest do |srcpath, destpath|
      File.open(srcpath, 'rb') {|src|
        File.open(destpath, 'wb') {|dest|
          copy_stream src, dest
        }
      }
      assert_same_file srcpath, destpath
    end
  end

  def test_copy_stream_duck
    check_singleton :copy_stream
    # duck typing test  [ruby-dev:25369]
    each_srcdest do |srcpath, destpath|
      File.open(srcpath, 'rb') {|src|
        File.open(destpath, 'wb') {|dest|
          copy_stream Stream.new(src), Stream.new(dest)
        }
      }
      assert_same_file srcpath, destpath
    end
  end

  def test_remove_file
    check_singleton :remove_file
    File.open('data/tmp', 'w') {|f| f.puts 'dummy' }
    remove_file 'data/tmp'
    assert_file_not_exist 'data/tmp'
  end

  def test_remove_file_file_perm
    File.open('data/tmp', 'w') {|f| f.puts 'dummy' }
    File.chmod 0o000, 'data/tmp'
    remove_file 'data/tmp'
    assert_file_not_exist 'data/tmp'
  end if have_file_perm?

  def test_remove_dir
    check_singleton :remove_dir
    Dir.mkdir 'data/tmpdir'
    File.open('data/tmpdir/a', 'w') {|f| f.puts 'dummy' }
    remove_dir 'data/tmpdir'
    assert_file_not_exist 'data/tmpdir'
  end

  def test_remove_dir_file_perm
    Dir.mkdir 'data/tmpdir'
    File.chmod 0o555, 'data/tmpdir'
    remove_dir 'data/tmpdir'
    assert_file_not_exist 'data/tmpdir'
  end if have_file_perm?

  def test_remove_dir_with_file
    File.write('data/tmpfile', 'dummy')
    assert_raise(Errno::ENOTDIR) { remove_dir 'data/tmpfile' }
    assert_file_exist 'data/tmpfile'
  ensure
    File.unlink('data/tmpfile') if File.exist?('data/tmpfile')
  end

  def test_compare_file
    check_singleton :compare_file
    # FIXME
  end

  def test_compare_stream
    check_singleton :compare_stream
    # FIXME
  end

  class Stream
    def initialize(f)
      @f = f
    end

    def read(*args)
      @f.read(*args)
    end

    def write(str)
      @f.write str
    end
  end

  def test_uptodate?
    check_singleton :uptodate?
    prepare_time_data
    Dir.chdir('data') {
      assert(   uptodate?('newest', %w(old newer notexist)) )
      assert( ! uptodate?('newer', %w(old newest notexist)) )
      assert( ! uptodate?('notexist', %w(old newest newer)) )
    }

    # pathname
    touch 'tmp/a'
    touch 'tmp/b'
    touch 'tmp/c'
    assert_nothing_raised {
      uptodate? Pathname.new('tmp/a'), ['tmp/b', 'tmp/c']
      uptodate? 'tmp/a', [Pathname.new('tmp/b'), 'tmp/c']
      uptodate? 'tmp/a', ['tmp/b', Pathname.new('tmp/c')]
      uptodate? Pathname.new('tmp/a'), [Pathname.new('tmp/b'), Pathname.new('tmp/c')]
    }
    # [Bug #6708] [ruby-core:46256]
    assert_raise_with_message(ArgumentError, /wrong number of arguments \(.*\b3\b.* 2\)/) {
      uptodate?('new',['old', 'oldest'], {})
    }
  end

  def test_cd
    check_singleton :cd
  end

  def test_cd_result
    assert_equal 42, cd('.') { 42 }
  end

  def test_chdir
    check_singleton :chdir
  end

  def test_chdir_verbose
    assert_output_lines(["cd .", "cd -"], FileUtils) do
      FileUtils.chdir('.', verbose: true){}
    end
  end

  def test_chdir_verbose_frozen
    o = Object.new
    o.extend(FileUtils)
    o.singleton_class.send(:public, :chdir)
    o.freeze
    orig_stdout = $stdout
    $stdout = StringIO.new
    o.chdir('.', verbose: true){}
    $stdout.rewind
    assert_equal(<<-END, $stdout.read)
cd .
cd -
    END
  ensure
    $stdout = orig_stdout if orig_stdout
  end

  def test_getwd
    check_singleton :getwd
  end

  def test_identical?
    check_singleton :identical?
  end

  def test_link
    check_singleton :link
  end

  def test_makedirs
    check_singleton :makedirs
  end

  def test_mkpath
    check_singleton :mkpath
  end

  def test_move
    check_singleton :move
  end

  def test_rm_rf
    check_singleton :rm_rf

    return if /mswin|mingw/ =~ RUBY_PLATFORM

    mkdir 'tmpdatadir'
    chmod 0o000, 'tmpdatadir'
    rm_rf 'tmpdatadir'

    assert_file_not_exist 'tmpdatadir'
  end

  def test_rmdir
    check_singleton :rmdir

    begin
      Dir.rmdir '/'
    rescue Errno::ENOTEMPTY
    rescue => e
      assert_raise(e.class) {
        # Dir.rmdir('') raises Errno::ENOENT.
        # FileUtils#rmdir ignores it.
        # And this test failed as expected.
        rmdir '/'
      }
    end

    subdir = 'data/sub/dir'
    mkdir_p(subdir)
    File.write("#{subdir}/file", '')
    msg = "should fail to remove non-empty directory"
    assert_raise(Errno::ENOTEMPTY, Errno::EEXIST, msg) {
      rmdir(subdir)
    }
    assert_raise(Errno::ENOTEMPTY, Errno::EEXIST, msg) {
      rmdir(subdir, parents: true)
    }
    File.unlink("#{subdir}/file")
    assert_raise(Errno::ENOENT) {
      rmdir("#{subdir}/nonexistent")
    }
    assert_raise(Errno::ENOENT) {
      rmdir("#{subdir}/nonexistent", parents: true)
    }
    assert_nothing_raised(Errno::ENOENT) {
      rmdir(subdir, parents: true)
    }
    assert_file_not_exist(subdir)
    assert_file_not_exist('data/sub')
    assert_directory('data')
  end

  def test_rmtree
    check_singleton :rmtree
  end

  def test_safe_unlink
    check_singleton :safe_unlink
  end

  def test_symlink
    check_singleton :symlink
  end

  def test_touch
    check_singleton :touch
  end

  def test_collect_methods
  end

  def test_commands
  end

  def test_have_option?
  end

  def test_options
  end

  def test_options_of
  end

end
