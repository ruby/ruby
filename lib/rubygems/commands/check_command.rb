require 'rubygems/command'
require 'rubygems/version_option'
require 'rubygems/validator'

class Gem::Commands::CheckCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'check', 'Check installed gems',
          :verify => false, :alien => false

    add_option(      '--verify FILE',
               'Verify gem file against its internal',
               'checksum') do |value, options|
      options[:verify] = value
    end

    add_option('-a', '--alien', "Report 'unmanaged' or rogue files in the",
               "gem repository") do |value, options|
      options[:alien] = true
    end

    add_option('-t', '--test', "Run unit tests for gem") do |value, options|
      options[:test] = true
    end

    add_version_option 'run tests for'
  end

  def execute
    if options[:test]
      version = options[:version] || Gem::Requirement.default
      dep = Gem::Dependency.new get_one_gem_name, version
      gem_spec = Gem::SourceIndex.from_installed_gems.search(dep).first
      Gem::Validator.new.unit_test(gem_spec)
    end

    if options[:alien]
      say "Performing the 'alien' operation"
      Gem::Validator.new.alien.each do |key, val|
        if(val.size > 0)
          say "#{key} has #{val.size} problems"
          val.each do |error_entry|
            say "\t#{error_entry.path}:"
            say "\t#{error_entry.problem}"
            say
          end
        else  
          say "#{key} is error-free"
        end
        say
      end
    end

    if options[:verify]
      gem_name = options[:verify]
      unless gem_name
        alert_error "Must specify a .gem file with --verify NAME"
        return
      end
      unless File.exist?(gem_name)
        alert_error "Unknown file: #{gem_name}."
        return
      end
      say "Verifying gem: '#{gem_name}'"
      begin
        Gem::Validator.new.verify_gem_file(gem_name)
      rescue Exception => e
        alert_error "#{gem_name} is invalid."
      end
    end
  end

end
