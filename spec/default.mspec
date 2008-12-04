load File.dirname(__FILE__) + '/rubyspec/ruby.1.9.mspec'
class MSpecScript
  builddir = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  srcdir = ENV['SRCDIR']
  srcdir ||= $1 if File.read("#{builddir}/Makefile")[/^\s*srcdir\s*=\s*(.+)/i]
  srcdir ||= builddir
  config = proc{|name| `#{builddir}/miniruby -I#{srcdir} -rrbconfig -e 'print Config::CONFIG["#{name}"]'`}

  # The default implementation to run the specs.
  set :target, File.join(builddir, "miniruby#{config['exeext']}")
  set :flags, %W[
    -I#{srcdir}/lib
    -I#{srcdir}/#{config['EXTOUT']}/common
    -I#{srcdir}/-
    -r#{srcdir}/ext/purelib.rb
    #{srcdir}/runruby.rb --extout=#{config['EXTOUT']}
  ]
end
