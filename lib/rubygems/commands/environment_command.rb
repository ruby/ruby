require 'rubygems/command'

class Gem::Commands::EnvironmentCommand < Gem::Command

  def initialize
    super 'environment', 'Display information about the RubyGems environment'
  end

  def arguments # :nodoc:
    args = <<-EOF
          packageversion  display the package version
          gemdir          display the path where gems are installed
          gempath         display path used to search for gems
          version         display the gem format version
          remotesources   display the remote gem servers
          <omitted>       display everything
    EOF
    return args.gsub(/^\s+/, '')
  end

  def description # :nodoc:
    <<-EOF
The RubyGems environment can be controlled through command line arguments,
gemrc files, environment variables and built-in defaults.

Command line argument defaults and some RubyGems defaults can be set in
~/.gemrc file for individual users and a /etc/gemrc for all users.  A gemrc
is a YAML file with the following YAML keys:

  :sources: A YAML array of remote gem repositories to install gems from
  :verbose: Verbosity of the gem command.  false, true, and :really are the
            levels
  :update_sources: Enable/disable automatic updating of repository metadata
  :backtrace: Print backtrace when RubyGems encounters an error
  :bulk_threshold: Switch to a bulk update when this many sources are out of
                   date (legacy setting)
  :gempath: The paths in which to look for gems
  gem_command: A string containing arguments for the specified gem command

Example:

  :verbose: false
  install: --no-wrappers
  update: --no-wrappers

RubyGems' default local repository can be overriden with the GEM_PATH and
GEM_HOME environment variables.  GEM_HOME sets the default repository to
install into.  GEM_PATH allows multiple local repositories to be searched for
gems.

If you are behind a proxy server, RubyGems uses the HTTP_PROXY,
HTTP_PROXY_USER and HTTP_PROXY_PASS environment variables to discover the
proxy server.

If you are packaging RubyGems all of RubyGems' defaults are in
lib/rubygems/defaults.rb.  You may override these in
lib/rubygems/defaults/operating_system.rb
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [arg]"
  end

  def execute
    out = ''
    arg = options[:args][0]
    case arg
    when /^packageversion/ then
      out << Gem::RubyGemsPackageVersion
    when /^version/ then
      out << Gem::RubyGemsVersion
    when /^gemdir/, /^gemhome/, /^home/, /^GEM_HOME/ then
      out << Gem.dir
    when /^gempath/, /^path/, /^GEM_PATH/ then
      out << Gem.path.join(File::PATH_SEPARATOR)
    when /^remotesources/ then
      out << Gem.sources.join("\n")
    when nil then
      out = "RubyGems Environment:\n"

      out << "  - RUBYGEMS VERSION: #{Gem::RubyGemsVersion}\n"

      out << "  - RUBY VERSION: #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}"
      out << " patchlevel #{RUBY_PATCHLEVEL}" if defined? RUBY_PATCHLEVEL
      out << ") [#{RUBY_PLATFORM}]\n"

      out << "  - INSTALLATION DIRECTORY: #{Gem.dir}\n"

      out << "  - RUBYGEMS PREFIX: #{Gem.prefix}\n" unless Gem.prefix.nil?

      out << "  - RUBY EXECUTABLE: #{Gem.ruby}\n"

      out << "  - EXECUTABLE DIRECTORY: #{Gem.bindir}\n"

      out << "  - RUBYGEMS PLATFORMS:\n"
      Gem.platforms.each do |platform|
        out << "    - #{platform}\n"
      end

      out << "  - GEM PATHS:\n"
      out << "     - #{Gem.dir}\n"

      path = Gem.path.dup
      path.delete Gem.dir
      path.each do |p|
        out << "     - #{p}\n"
      end

      out << "  - GEM CONFIGURATION:\n"
      Gem.configuration.each do |name, value|
        out << "     - #{name.inspect} => #{value.inspect}\n"
      end

      out << "  - REMOTE SOURCES:\n"
      Gem.sources.each do |s|
        out << "     - #{s}\n"
      end

    else
      raise Gem::CommandLineError, "Unknown enviroment option [#{arg}]"
    end
    say out
    true
  end

end

