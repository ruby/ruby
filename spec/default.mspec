class MSpecScript
  # An ordered list of the directories containing specs to run
  # as the CI process.
  set :ci_files, %w[
    spec/rubyspec/1.9/core
    spec/rubyspec/1.9/language
    spec/rubyspec/1.9/library
  ]

  srcdir = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  config = proc{|name| `#{srcdir}/miniruby -I#{srcdir} -rrbconfig -e 'print Config::CONFIG["#{name}"]'`}

  # The default implementation to run the specs.
  set :target, File.join(srcdir, "miniruby#{config['exeext']}")
  set :flags, %W[
    -I#{srcdir}/lib
    -I#{srcdir}/#{config['EXTOUT']}/common
    -I#{srcdir}/-
    -r#{srcdir}/ext/purelib.rb
    #{srcdir}/runruby.rb --extout=#{config['EXTOUT']}
  ]
end
