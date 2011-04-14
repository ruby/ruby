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
p Foo::Bar
      INPUT
    end
    open(tmpfiles[1], 'w') do |f|
      f.puts 'class Foo::Bar; end'
    end
    assert_in_out_err([tmpfiles[0]], "", ["Foo::Bar"], [])
  ensure
    File.unlink(*tmpfiles) rescue nil if tmpfiles
    tmpdirs.each {|dir| Dir.rmdir(dir)}
  end

  def test_autoload_p
    bug4565 = '[ruby-core:35679]'

    require 'tmpdir'
    tmpdir = Dir.mktmpdir('autoload')
    tmpfile = tmpdir + '/foo.rb'
    a = Module.new do
      autoload :X, tmpfile
    end
    b = Module.new do
      include a
    end
    assert_equal(true, a.const_defined?(:X))
    assert_equal(true, b.const_defined?(:X))
    assert_equal(tmpfile, a.autoload?(:X), bug4565)
    assert_equal(tmpfile, b.autoload?(:X), bug4565)
  end
end
