require 'test/unit'
require_relative 'envutil'

class TestAutoload < Test::Unit::TestCase
  def test_autoload_so
    # Continuation is always available, unless excluded intentionally.
    assert_in_out_err([], <<-INPUT, [], [])
    autoload :Continuation, "continuation"
    begin Continuation; rescue LoadError; end
    INPUT
  end

  def test_non_realpath_in_loadpath
    require 'tmpdir'
    tmpdir = Dir.mktmpdir('autoload')
    tmpdirs = [tmpdir]
    tmpdirs.unshift(tmpdir + '/foo')
    Dir.mkdir(tmpdirs[0])
    tmpfiles = [tmpdir + '/foo.rb', tmpdir + '/foo/bar.rb']
    open(tmpfiles[0] , 'w') do |f|
      f.puts <<-INPUT
$:.unshift(File.expand_path('..', __FILE__)+'/./foo')
module Foo
  autoload :Bar, 'bar'
end
Foo::Bar
      INPUT
    end
    open(tmpfiles[1], 'w') do |f|
      f.puts 'class Foo::Bar; end'
    end
    assert_in_out_err([tmpfiles[0]], "", [], [])
  ensure
    File.unlink(*tmpfiles) rescue nil if tmpfiles
    tmpdirs.each {|dir| Dir.rmdir(dir)}
  end
end
