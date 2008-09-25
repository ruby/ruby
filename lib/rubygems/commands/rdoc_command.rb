require 'rubygems/command'
require 'rubygems/version_option'
require 'rubygems/doc_manager'

module Gem
  module Commands
    class RdocCommand < Command
      include VersionOption

      def initialize
        super('rdoc',
          'Generates RDoc for pre-installed gems',
          {
            :version => Gem::Requirement.default,
            :include_rdoc => true,
            :include_ri => true,
          })
        add_option('--all',
                   'Generate RDoc/RI documentation for all',
                   'installed gems') do |value, options|
          options[:all] = value
        end
        add_option('--[no-]rdoc', 
          'Include RDoc generated documents') do
          |value, options|
          options[:include_rdoc] = value
        end
        add_option('--[no-]ri', 
          'Include RI generated documents'
          ) do |value, options|
          options[:include_ri] = value
        end
        add_version_option
      end

      def arguments # :nodoc:
        "GEMNAME       gem to generate documentation for (unless --all)"
      end

      def defaults_str # :nodoc:
        "--version '#{Gem::Requirement.default}' --rdoc --ri"
      end

      def usage # :nodoc:
        "#{program_name} [args]"
      end

      def execute
        if options[:all]
          specs = Gem::SourceIndex.from_installed_gems.collect { |name, spec|
            spec
          }
        else
          gem_name = get_one_gem_name
          specs = Gem::SourceIndex.from_installed_gems.search(
            gem_name, options[:version])
        end

        if specs.empty?
          fail "Failed to find gem #{gem_name} to generate RDoc for #{options[:version]}"
        end

        if options[:include_ri]
          specs.each do |spec|
            Gem::DocManager.new(spec).generate_ri
          end

          Gem::DocManager.update_ri_cache
        end

        if options[:include_rdoc]
          specs.each do |spec|
            Gem::DocManager.new(spec).generate_rdoc
          end
        end

        true
      end
    end

  end
end
