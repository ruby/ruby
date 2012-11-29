require 'rubygems/command'
require 'rubygems/version_option'
require 'rubygems/validator'

class Gem::Commands::CheckCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'check', 'Check installed gems',
          :alien => true

    add_option('-a', '--alien', "Report 'unmanaged' or rogue files in the",
               "gem repository") do |value, options|
      options[:alien] = true
    end

    add_version_option 'check'
  end

  def execute
    say "Checking gems..."
    say
    gems = get_all_gem_names rescue []

    Gem::Validator.new.alien(gems).sort.each do |key, val|
      unless val.empty? then
        say "#{key} has #{val.size} problems"
        val.each do |error_entry|
          say "  #{error_entry.path}:"
          say "    #{error_entry.problem}"
        end
      else
        say "#{key} is error-free" if Gem.configuration.verbose
      end
      say
    end
  end

end
