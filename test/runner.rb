require 'rbconfig'
exit if CROSS_COMPILING

require 'test/unit'

src_testdir = File.dirname(File.expand_path(__FILE__))
srcdir = File.dirname(src_testdir)

tests = Test::Unit.new {|files, options|
  options[:base_directory] = src_testdir
  if files.empty?
    [src_testdir]
  else
    files
  end
}
exit tests.run(ARGV) || true
