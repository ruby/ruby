#
# test/fileutils/test_fileutils.rb
#

$:.unshift File.dirname(__FILE__)

require 'fileutils'
require 'fileasserts'
require 'pathname'
require 'tmpdir'
require 'test/unit'

class TestFileUtils < Test::Unit::TestCase
  TMPROOT = "#{Dir.tmpdir}/fileutils.rb.#{$$}"
end

prevdir = Dir.pwd
tmproot = TestFileUtils::TMPROOT
Dir.mkdir tmproot unless File.directory?(tmproot)
Dir.chdir tmproot

def have_drive_letter?
  /djgpp|mswin(?!ce)|mingw|bcc|emx/ === RUBY_PLATFORM
end

def have_file_perm?
  /djgpp|mswin|mingw|bcc|wince|emx/ !~ RUBY_PLATFORM
end

begin
  File.symlink 'not_exist', 'symlink_test'
  HAVE_SYMLINK = true
rescue NotImplementedError
  HAVE_SYMLINK = false
ensure
  File.unlink 'symlink_test' if File.symlink?('symlink_test')
end
def have_symlink?
  HAVE_SYMLINK
end

begin
  File.open('linktmp', 'w') {|f| f.puts 'dummy' }
  File.link 'linktmp', 'linktest'
  HAVE_HARDLINK = true
rescue NotImplementedError, SystemCallError
  HAVE_HARDLINK = false
ensure
  File.unlink 'linktest' if File.exist?('linktest')
  File.unlink 'linktmp' if File.exist?('linktmp')
end
def have_hardlink?
  HAVE_HARDLINK
end

Dir.chdir prevdir
Dir.rmdir tmproot

class TestFileUtils

  include FileUtils

  def my_rm_rf( path )
    if File.exist?('/bin/rm')
      system %Q[/bin/rm -rf "#{path}"]
    else
      FileUtils.rm_rf path
    end
  end

  def setup
    @prevdir = Dir.pwd
    tmproot = "#{Dir.tmpdir}/fileutils.rb.#{$$}"
    Dir.mkdir tmproot unless File.directory?(tmproot)
    Dir.chdir tmproot
    my_rm_rf 'data'; Dir.mkdir 'data'
    my_rm_rf 'tmp';  Dir.mkdir 'tmp'
    prepare_data_file
    prepare_time_data
  end

  def teardown
    tmproot = Dir.pwd
    Dir.chdir @prevdir
    my_rm_rf tmproot
  end


  TARGETS = %w( data/same data/all data/random data/zero )

  def prepare_data_file
    same_chars = 'a' * 50
    File.open('data/same', 'w') {|f|
      32.times do
        f.puts same_chars
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

  def test_pwd
    assert_equal Dir.pwd, pwd()

    cwd = Dir.pwd
if have_drive_letter?
    cd('C:/') {
      assert_equal 'C:/', pwd()
    }
    assert_equal cwd, pwd()
else
    cd('/') {
      assert_equal '/', pwd()
    }
    assert_equal cwd, pwd()
end
  end

  def test_cmp
    TARGETS.each do |fname|
      assert cmp(fname, fname), 'not same?'
    end
    assert_raises(ArgumentError) {
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
    TARGETS.each do |fname|
      cp fname, 'tmp/cp'
      assert_same_file fname, 'tmp/cp'

      cp fname, 'tmp'
      assert_same_file fname, 'tmp/' + File.basename(fname)

      cp fname, 'tmp/'
      assert_same_file fname, 'tmp/' + File.basename(fname)

      cp fname, 'tmp/preserve', :preserve => true
      assert_same_file fname, 'tmp/preserve'
      a = File.stat(fname)
      b = File.stat('tmp/preserve')
      assert_equal a.mode, b.mode
      assert_equal a.mtime, b.mtime
      assert_equal a.uid, b.uid
      assert_equal a.gid, b.gid
    end

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raises(ArgumentError) {
      cp 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raises(ArgumentError) {
      cp 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    assert_raises(ArgumentError) {
      cp 'tmp/cptmp_symlink', 'tmp/cptmp'
    }
    # src==dest (3) looped symlink
    File.symlink 'symlink', 'tmp/symlink'
    assert_raises(Errno::ELOOP) {
      cp 'tmp/symlink', 'tmp/symlink'
    }
end

    # pathname
    assert_nothing_raised {
      cp 'tmp/cptmp', Pathname.new('tmp/tmpdest')
      cp Pathname.new('tmp/cptmp'), 'tmp/tmpdest'
      cp Pathname.new('tmp/cptmp'), Pathname.new('tmp/tmpdest')
      mkdir 'tmp/tmpdir'
      cp ['tmp/cptmp', 'tmp/tmpdest'], Pathname.new('tmp/tmpdir')
    }
  end

  def test_cp_r
    cp_r 'data', 'tmp'
    TARGETS.each do |fname|
      assert_same_file fname, "tmp/#{fname}"
    end

    # pathname
    touch 'tmp/cprtmp'
    assert_nothing_raised {
      cp_r Pathname.new('tmp/cprtmp'), 'tmp/tmpdest'
      cp_r 'tmp/cprtmp', Pathname.new('tmp/tmpdest')
      cp_r Pathname.new('tmp/cprtmp'), Pathname.new('tmp/tmpdest')
    }
  end

  def test_mv
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

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raises(ArgumentError) {
      mv 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raises(ArgumentError) {
      mv 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    assert_raises(ArgumentError) {
      mv 'tmp/cptmp_symlink', 'tmp/cptmp'
    }
    # src==dest (3) looped symlink
    File.symlink 'symlink', 'tmp/symlink'
    assert_raises(Errno::ELOOP) {
      mv 'tmp/symlink', 'tmp/symlink'
    }
end

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
    TARGETS.each do |fname|
      cp fname, 'tmp/rmsrc'
      rm_f 'tmp/rmsrc'
      assert_file_not_exist 'tmp/rmsrc'
    end

if have_symlink?
    File.open('tmp/lnf_symlink_src', 'w') {|f| f.puts 'dummy' }
    File.symlink 'tmp/lnf_symlink_src', 'tmp/lnf_symlink_dest'
    rm_f 'tmp/lnf_symlink_dest'
    assert_file_not_exist 'tmp/lnf_symlink_dest'
    assert_file_exist     'tmp/lnf_symlink_src'
end

    rm_f 'notexistdatafile'
    rm_f 'tmp/notexistdatafile'
    my_rm_rf 'tmpdatadir'
    Dir.mkdir 'tmpdatadir'
    # rm_f 'tmpdatadir'
    Dir.rmdir 'tmpdatadir'

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
  end

  def test_rm_r
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

if have_hardlink?
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
    assert_raises(Errno::EEXIST) {
      ln 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/symlink'
    assert_raises(Errno::EEXIST) {
      ln 'tmp/cptmp', 'tmp/symlink'   # normal file -> symlink
    }
    assert_raises(Errno::EEXIST) {
      ln 'tmp/symlink', 'tmp/cptmp'   # symlink -> normal file
    }
    # src==dest (3) looped symlink
    File.symlink 'cptmp_symlink', 'tmp/cptmp_symlink'
    begin
      ln 'tmp/cptmp_symlink', 'tmp/cptmp_symlink'
    rescue => err
      assert_kind_of SystemCallError, err
    end
end

    # pathname
    touch 'tmp/lntmp'
    assert_nothing_raised {
      ln Pathname.new('tmp/lntmp'), 'tmp/lndesttmp1'
      ln 'tmp/lntmp', Pathname.new('tmp/lndesttmp2')
      ln Pathname.new('tmp/lntmp'), Pathname.new('tmp/lndesttmp3')
    }
  end
end

if have_symlink?
  def test_ln_s
    TARGETS.each do |fname|
      ln_s fname, 'tmp/lnsdest'
      assert FileTest.symlink?('tmp/lnsdest'), 'not symlink'
      assert_equal fname, File.readlink('tmp/lnsdest')
      rm_f 'tmp/lnsdest'
    end
    assert_nothing_raised {
      ln_s 'symlink', 'tmp/symlink'
    }
    assert_symlink 'tmp/symlink'

    # pathname
    touch 'tmp/lnsdest'
    assert_nothing_raised {
      ln_s Pathname.new('lnsdest'), 'tmp/symlink_tmp1'
      ln_s 'lnsdest', Pathname.new('tmp/symlink_tmp2')
      ln_s Pathname.new('lnsdest'), Pathname.new('tmp/symlink_tmp3')
    }
  end
end

if have_symlink?
  def test_ln_sf
    TARGETS.each do |fname|
      ln_sf fname, 'tmp/lnsdest'
      assert FileTest.symlink?('tmp/lnsdest'), 'not symlink'
      assert_equal fname, File.readlink('tmp/lnsdest')
      ln_sf fname, 'tmp/lnsdest'
      ln_sf fname, 'tmp/lnsdest'
    end
    assert_nothing_raised {
      ln_sf 'symlink', 'tmp/symlink'
    }

    # pathname
    touch 'tmp/lns_dest'
    assert_nothing_raised {
      ln_sf Pathname.new('lns_dest'), 'tmp/symlink_tmp1'
      ln_sf 'lns_dest', Pathname.new('tmp/symlink_tmp2')
      ln_sf Pathname.new('lns_dest'), Pathname.new('tmp/symlink_tmp3')
    }
  end
end

  def test_mkdir
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
    assert_equal 0700, (File.stat('tmp/tmp').mode & 0777) if have_file_perm?
    Dir.rmdir 'tmp/tmp'

    # pathname
    assert_nothing_raised {
      mkdir Pathname.new('tmp/tmpdirtmp')
      mkdir [Pathname.new('tmp/tmpdirtmp2'), Pathname.new('tmp/tmpdirtmp3')]
    }
  end

  def test_mkdir_p
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
    rm_rf 'tmpdir'
    dirs.each do |d|
      mkdir_p d
      assert_directory d
      assert_file_not_exist "#{d}/a"
      assert_file_not_exist "#{d}/b"
      assert_file_not_exist "#{d}/c"
      rm_rf 'tmpdir'
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
    assert_equal 0700, (File.stat('tmp/tmp').mode & 0777) if have_file_perm?
    assert_equal 0700, (File.stat('tmp/tmp/tmp').mode & 0777) if have_file_perm?
    rm_rf 'tmp/tmp'

    # pathname
    assert_nothing_raised {
      mkdir_p Pathname.new('tmp/tmp/tmp')
    }
  end

  def test_uptodate?
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
  end

  def test_install
    File.open('tmp/aaa', 'w') {|f| f.puts 'aaa' }
    File.open('tmp/bbb', 'w') {|f| f.puts 'bbb' }
    install 'tmp/aaa', 'tmp/bbb', :mode => 0600
    assert_equal "aaa\n", File.read('tmp/bbb')
    assert_equal 0600, (File.stat('tmp/bbb').mode & 0777) if have_file_perm?

    t = File.mtime('tmp/bbb')
    install 'tmp/aaa', 'tmp/bbb'
    assert_equal "aaa\n", File.read('tmp/bbb')
    assert_equal 0600, (File.stat('tmp/bbb').mode & 0777) if have_file_perm?
    assert_equal t, File.mtime('tmp/bbb')

    File.unlink 'tmp/aaa'
    File.unlink 'tmp/bbb'

    # src==dest (1) same path
    touch 'tmp/cptmp'
    assert_raises(ArgumentError) {
      install 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    # src==dest (2) symlink and its target
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raises(ArgumentError) {
      install 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    assert_raises(ArgumentError) {
      install 'tmp/cptmp_symlink', 'tmp/cptmp'
    }
    # src==dest (3) looped symlink
    File.symlink 'symlink', 'tmp/symlink'
    assert_raises(Errno::ELOOP) {
      # File#install invokes open(2), always ELOOP must be raised
      install 'tmp/symlink', 'tmp/symlink'
    }
end

    # pathname
    assert_nothing_raised {
      rm_f 'tmp/a'; touch 'tmp/a'
      install 'tmp/a', Pathname.new('tmp/b')
      rm_f 'tmp/a'; touch 'tmp/a'
      install Pathname.new('tmp/a'), 'tmp/b'
      rm_f 'tmp/a'; touch 'tmp/a'
      install Pathname.new('tmp/a'), Pathname.new('tmp/b')
      rm_f 'tmp/a'
      touch 'tmp/a'
      touch 'tmp/b'
      mkdir 'tmp/dest'
      install [Pathname.new('tmp/a'), Pathname.new('tmp/b')], 'tmp/dest'
      rm_rf 'tmp/dest'
      mkdir 'tmp/dest'
      install [Pathname.new('tmp/a'), Pathname.new('tmp/b')], Pathname.new('tmp/dest')
    }
  end

end
