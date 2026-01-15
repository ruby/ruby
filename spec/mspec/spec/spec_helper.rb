RSpec.configure do |config|
  config.disable_monkey_patching!
  config.raise_errors_for_deprecations!
end

require 'mspec'

# Remove this when MRI has intelligent warnings
$VERBOSE = nil unless $VERBOSE

class MOSConfig < Hash
  def initialize
    self[:loadpath]  = []
    self[:requires]  = []
    self[:flags]     = []
    self[:options]   = []
    self[:includes]  = []
    self[:excludes]  = []
    self[:patterns]  = []
    self[:xpatterns] = []
    self[:tags]      = []
    self[:xtags]     = []
    self[:atags]     = []
    self[:astrings]  = []
    self[:target]    = 'ruby'
    self[:command]   = nil
    self[:ltags]     = []
    self[:files]     = []
    self[:launch]    = []
  end
end

def new_option
  config = MOSConfig.new
  return MSpecOptions.new("spec", 20, config), config
end

# Just to have an exception name output not be "Exception"
class MSpecExampleError < Exception
end

def hide_deprecation_warnings
  allow(MSpec).to receive(:deprecate)
end

def run_mspec(command, args)
  cwd = Dir.pwd
  command = " #{command}" unless command.start_with?('-')
  cmd = "#{cwd}/bin/mspec#{command} -B spec/fixtures/config.mspec #{args}"
  out = `#{cmd} 2>&1`
  ret = $?
  out = out.sub(/\A\$.+\n/, '') # Remove printed command line
  out = out.sub(RUBY_DESCRIPTION, "RUBY_DESCRIPTION")
  out = out.gsub(/\d+\.\d{6}/, "D.DDDDDD") # Specs total time
  out = out.gsub(/\d{2}:\d{2}:\d{2}/, "00:00:00") # Progress bar time
  out = out.gsub(cwd, "CWD")
  return out, ret
end

def ensure_mspec_method(method)
  file, _line = method.source_location
  expect(file).to start_with(File.expand_path('../../lib/mspec', __FILE__ ))
end

PublicMSpecMatchers = Class.new {
  include MSpecMatchers
  public :raise_error
}.new

BACKTRACE_QUOTE = RUBY_VERSION >= "3.4" ? "'" : "`"
