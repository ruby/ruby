# frozen_string_literal: false
require 'rubygems/command'
require 'rubygems/package'

class Gem::Commands::BuildCommand < Gem::Command

  def initialize
    super 'build', 'Build a gem from a gemspec'

    add_option '--force', 'skip validation of the spec' do |value, options|
      options[:force] = true
    end
  end

  def arguments # :nodoc:
    "GEMSPEC_FILE  gemspec file name to build a gem for"
  end

  def description # :nodoc:
    <<-EOF
The build command allows you to create a gem from a ruby gemspec.

The best way to build a gem is to use a Rakefile and the Gem::PackageTask
which ships with RubyGems.

The gemspec can either be created by hand or extracted from an existing gem
with gem spec:

  $ gem unpack my_gem-1.0.gem
  Unpacked gem: '.../my_gem-1.0'
  $ gem spec my_gem-1.0.gem --ruby > my_gem-1.0/my_gem-1.0.gemspec
  $ cd my_gem-1.0
  [edit gem contents]
  $ gem build my_gem-1.0.gemspec
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMSPEC_FILE"
  end

  def execute
    gemspec = get_one_gem_name

    if File.exist? gemspec then
      spec = Gem::Specification.load gemspec

      if spec then
        Gem::Package.build spec, options[:force]
      else
        alert_error "Error loading gemspec. Aborting."
        terminate_interaction 1
      end
    else
      alert_error "Gemspec file not found: #{gemspec}"
      terminate_interaction 1
    end
  end

end

