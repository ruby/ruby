use_realpath = File.respond_to?(:realpath)
root = File.dirname(__FILE__)
dir = "fixtures/code"
CODE_LOADING_DIR = use_realpath ? File.realpath(dir, root) : File.expand_path(dir, root)

# Reserve names.
def reserve_names(*names)
  names.each  do |name|
    fail "Name #{name} is already in use" if ENV.include?(name)
  end
  @reserved_names = names
end

# Release reserved names.
def release_names
  @reserved_names.each do |name|
    ENV.delete(name)
  end
end

# Mock object for calling to_str.
def mock_to_str(s)
  mock_object = mock('name')
  mock_object.should_receive(:to_str).and_return(s.to_s)
  mock_object
end

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

# Running directly with ruby some_spec.rb
unless ENV['MSPEC_RUNNER']
  mspec_lib = File.expand_path("../../mspec/lib", __FILE__)
  $LOAD_PATH << mspec_lib if File.directory?(mspec_lib)

  begin
    require 'mspec'
    require 'mspec/commands/mspec-run'
  rescue LoadError
    puts "Please add -Ipath/to/mspec/lib or clone mspec as a sibling to run the specs."
    exit 1
  end

  ARGV.unshift $0
  MSpecRun.main
end
