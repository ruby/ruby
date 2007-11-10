require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/source_info_cache'

class Gem::Commands::DependencyCommand < Gem::Command

  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super 'dependency',
          'Show the dependencies of an installed gem',
          :version => Gem::Requirement.default, :domain => :local

    add_version_option
    add_platform_option

    add_option('-R', '--[no-]reverse-dependencies',
               'Include reverse dependencies in the output') do
      |value, options|
      options[:reverse_dependencies] = value
    end

    add_option('-p', '--pipe',
               "Pipe Format (name --version ver)") do |value, options|
      options[:pipe_format] = value
    end

    add_local_remote_options
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to show dependencies for"
  end

  def defaults_str # :nodoc:
    "--local --version '#{Gem::Requirement.default}' --no-reverse-dependencies"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME"
  end

  def execute
    options[:args] << '.' if options[:args].empty?
    specs = {}

    source_indexes = []

    if local? then
      source_indexes << Gem::SourceIndex.from_installed_gems
    end

    if remote? then
      Gem::SourceInfoCache.cache_data.map do |_, sice|
        source_indexes << sice.source_index
      end
    end

    options[:args].each do |name|
      new_specs = nil
      source_indexes.each do |source_index|
        new_specs =  find_gems(name, source_index)
      end

      say "No match found for #{name} (#{options[:version]})" if
        new_specs.empty?

      specs = specs.merge new_specs
    end

    terminate_interaction 1 if specs.empty?

    reverse = Hash.new { |h, k| h[k] = [] }

    if options[:reverse_dependencies] then
      specs.values.each do |source_index, spec|
        reverse[spec.full_name] = find_reverse_dependencies spec, source_index
      end
    end

    if options[:pipe_format] then
      specs.values.sort_by { |_, spec| spec }.each do |_, spec|
        unless spec.dependencies.empty?
          spec.dependencies.each do |dep|
            say "#{dep.name} --version '#{dep.version_requirements}'"
          end
        end
      end
    else
      response = ''

      specs.values.sort_by { |_, spec| spec }.each do |_, spec|
        response << print_dependencies(spec)
        unless reverse[spec.full_name].empty? then
          response << "  Used by\n"
          reverse[spec.full_name].each do |sp, dep|
            response << "    #{sp} (#{dep})\n"
          end
        end
        response << "\n"
      end

      say response
    end
  end

  def print_dependencies(spec, level = 0)
    response = ''
    response << '  ' * level + "Gem #{spec.full_name}\n"
    unless spec.dependencies.empty? then
      spec.dependencies.each do |dep|
        response << '  ' * level + "  #{dep}\n"
      end
    end
    response
  end

  # Retuns list of [specification, dep] that are satisfied by spec.
  def find_reverse_dependencies(spec, source_index)
    result = []

    source_index.each do |name, sp|
      sp.dependencies.each do |dep|
        dep = Gem::Dependency.new(*dep) unless Gem::Dependency === dep

        if spec.name == dep.name and
           dep.version_requirements.satisfied_by?(spec.version) then
          result << [sp.full_name, dep]
        end
      end
    end

    result
  end

  def find_gems(name, source_index)
    specs = {}

    spec_list = source_index.search name, options[:version]

    spec_list.each do |spec|
      specs[spec.full_name] = [source_index, spec]
    end

    specs
  end
end

