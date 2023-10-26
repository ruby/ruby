use_realpath = File.respond_to?(:realpath)
root = __dir__
dir = "fixtures/code"
CODE_LOADING_DIR = use_realpath ? File.realpath(dir, root) : File.expand_path(dir, root)

# Enable Thread.report_on_exception by default to catch thread errors earlier
if Thread.respond_to? :report_on_exception=
  Thread.report_on_exception = true
else
  class Thread
    def report_on_exception=(value)
      raise "shim Thread#report_on_exception used with true" if value
    end
  end
end

unless ENV['MSPEC_RUNNER'] # Running directly with ruby some_spec.rb
  mspec_lib = File.expand_path("../../mspec/lib", __FILE__)
  $LOAD_PATH << mspec_lib if File.directory?(mspec_lib)

  begin
    require 'mspec'
    require 'mspec/commands/mspec-run'
  rescue LoadError
    puts "Please add -Ipath/to/mspec/lib or clone mspec as a sibling to run the specs."
    exit 1
  end
end

# Compare with SpecVersion directly here so it works even with --unguarded
if VersionGuard::FULL_RUBY_VERSION < SpecVersion.new('2.7')
  abort "This version of ruby/spec requires Ruby 2.7+"
end

unless ENV['MSPEC_RUNNER'] # Running directly with ruby some_spec.rb
  ARGV.unshift $0
  MSpecRun.main
end
