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
      fail Gem::CommandLineError, "Unknown enviroment option [#{arg}]"
    end
    say out
    true
  end

end

