#
# test/fileutils/test_fileutils.rb
#

$:.unshift File.dirname(__FILE__)

require 'fileutils'
require 'fileasserts'
require 'tmpdir'
require 'test/unit'


def have_drive_letter?
  /djgpp|mswin|mingw|bcc|wince|emx/ === RUBY_PLATFORM
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


class TestFileUtils < Test::Unit::TestCase

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
  end

  def test_cp
    TARGETS.each do |fname|
      cp fname, 'tmp/cp'
      assert_same_file fname, 'tmp/cp'

      cp fname, 'tmp'
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

    # src==dest
    touch 'tmp/cptmp'
    assert_raises(ArgumentError) {
      cp 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raises(ArgumentError) {
      cp 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    File.symlink 'symlink', 'tmp/symlink'
    assert_raises(Errno::ELOOP) {
      cp 'tmp/symlink', 'tmp/symlink'
    }
end
  end

  def test_cp_r
    cp_r 'data', 'tmp'
    TARGETS.each do |fname|
      assert_same_file fname, "tmp/#{fname}"
    end
  end

  def test_mv
    TARGETS.each do |fname|
      cp fname, 'tmp/mvsrc'
      mv 'tmp/mvsrc', 'tmp/mvdest'
      assert_same_file fname, 'tmp/mvdest'
    end

    # src==dest
    touch 'tmp/cptmp'
    assert_raises(ArgumentError) {
      mv 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raises(ArgumentError) {
      mv 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    File.symlink 'symlink', 'tmp/symlink'
    assert_raises(Errno::ELOOP) {
      mv 'tmp/symlink', 'tmp/symlink'
    }
end
  end

  def test_rm
    TARGETS.each do |fname|
      cp fname, 'tmp/rmsrc'
      rm 'tmp/rmsrc'
      assert_file_not_exist 'tmp/rmsrc'
    end
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

    # src==dest
    touch 'tmp/cptmp'
    assert_raises(Errno::EEXIST) {
      ln 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    File.symlink 'tmp/cptmp', 'tmp/cptmp_symlink'
    assert_raises(Errno::EEXIST) {
      ln 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    File.symlink '.', 'tmp/symlink'
    assert_raises(Errno::EEXIST) {
      ln 'tmp/symlink', 'tmp/symlink'
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
      ln_s 'tmp/symlink', 'tmp/symlink'
    }
    assert_symlink 'tmp/symlink'
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
  end
end

  def test_mkdir
    my_rm_rf 'tmpdatadir'
    mkdir 'tmpdatadir'
    assert_directory 'tmpdatadir'
    Dir.rmdir 'tmpdatadir'

    mkdir 'tmp/mkdirdest'
    assert_directory 'tmp/mkdirdest'
    Dir.rmdir 'tmp/mkdirdest'

    mkdir 'tmp/tmp', :mode => 0700
    assert_directory 'tmp/tmp'
    assert_equal 0700, (File.stat('tmp/tmp').mode & 0777) if have_file_perm?
    Dir.rmdir 'tmp/tmp'
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

    mkdir_p 'tmp/tmp/tmp', :mode => 0700
    assert_directory 'tmp/tmp'
    assert_directory 'tmp/tmp/tmp'
    assert_equal 0700, (File.stat('tmp/tmp').mode & 0777) if have_file_perm?
    assert_equal 0700, (File.stat('tmp/tmp/tmp').mode & 0777) if have_file_perm?
    rm_rf 'tmp/tmp'
  end

  def try_mkdirp( dirs, del )
  end

  def test_uptodate?
    Dir.chdir('data') {
      assert(   uptodate?('newest', %w(old newer notexist)) )
      assert( ! uptodate?('newer', %w(old newest notexist)) )
      assert( ! uptodate?('notexist', %w(old newest newer)) )
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

    # src==dest
    touch 'tmp/cptmp'
    assert_raises(ArgumentError) {
      install 'tmp/cptmp', 'tmp/cptmp'
    }
if have_symlink?
    File.symlink 'cptmp', 'tmp/cptmp_symlink'
    assert_raises(ArgumentError) {
      install 'tmp/cptmp', 'tmp/cptmp_symlink'
    }
    File.symlink 'symlink', 'tmp/symlink'
    assert_raises(Errno::ELOOP) {
      install 'tmp/symlink', 'tmp/symlink'
    }
end
  end

end
