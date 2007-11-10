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
    if begins?("packageversion", arg) then
      out << Gem::RubyGemsPackageVersion
    elsif begins?("version", arg) then
      out << Gem::RubyGemsVersion
    elsif begins?("gemdir", arg) then
      out << Gem.dir
    elsif begins?("gempath", arg) then
      out << Gem.path.join("\n")
    elsif begins?("remotesources", arg) then
      out << Gem.sources.join("\n")
    elsif arg then
      fail Gem::CommandLineError, "Unknown enviroment option [#{arg}]"
    else
      out = "RubyGems Environment:\n"

      out << "  - RUBYGEMS VERSION: #{Gem::RubyGemsVersion} (#{Gem::RubyGemsPackageVersion})\n"

      out << "  - RUBY VERSION: #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}"
      out << " patchlevel #{RUBY_PATCHLEVEL}" if defined? RUBY_PATCHLEVEL
      out << ") [#{RUBY_PLATFORM}]\n"

      out << "  - INSTALLATION DIRECTORY: #{Gem.dir}\n"

      out << "  - RUBYGEMS PREFIX: #{Gem.prefix}\n" unless Gem.prefix.nil?

      out << "  - RUBY EXECUTABLE: #{Gem.ruby}\n"

      out << "  - RUBYGEMS PLATFORMS:\n"
      Gem.platforms.each do |platform|
        out << "    - #{platform}\n"
      end

      out << "  - GEM PATHS:\n"
      Gem.path.each do |p|
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
    end
    say out
    true
  end

end

