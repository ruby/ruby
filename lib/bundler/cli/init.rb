# frozen_string_literal: true
module Bundler
  class CLI::Init
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      if File.exist?("Gemfile")
        Bundler.ui.error "Gemfile already exists at #{SharedHelpers.pwd}/Gemfile"
        exit 1
      end

      if options[:gemspec]
        gemspec = File.expand_path(options[:gemspec])
        unless File.exist?(gemspec)
          Bundler.ui.error "Gem specification #{gemspec} doesn't exist"
          exit 1
        end
        spec = Gem::Specification.load(gemspec)
        puts "Writing new Gemfile to #{SharedHelpers.pwd}/Gemfile"
        File.open("Gemfile", "wb") do |file|
          file << "# Generated from #{gemspec}\n"
          file << spec.to_gemfile
        end
      else
        puts "Writing new Gemfile to #{SharedHelpers.pwd}/Gemfile"
        FileUtils.cp(File.expand_path("../../templates/Gemfile", __FILE__), "Gemfile")
      end
    end
  end
end
