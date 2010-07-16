require 'rbconfig'
exit if CROSS_COMPILING

require 'test/unit'

src_testdir = File.dirname(File.expand_path(__FILE__))
srcdir = File.dirname(src_testdir)

Test::Unit.setup_argv {|files|
  if files.empty?
    [src_testdir]
  else
    files.map {|f|
      if File.exist? "#{src_testdir}/#{f}"
        "#{src_testdir}/#{f}"
      elsif File.exist? "#{srcdir}/#{f}"
        "#{srcdir}/#{f}"
      elsif File.exist? f
        f
      else
        raise ArgumentError, "not found: #{f}"
      end
    }
  end
}
