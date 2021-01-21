# frozen_string_literal: true

require "pathname"

require "rubygems/specification"

# Possible use in Gem::Specification#source below and require
# shouldn't be deferred.
require "rubygems/source"

require_relative "match_platform"

module Gem
  class Specification
    attr_accessor :remote, :location, :relative_loaded_from

    remove_method :source
    attr_writer :source
    def source
      (defined?(@source) && @source) || Gem::Source::Installed.new
    end

    alias_method :rg_full_gem_path, :full_gem_path
    alias_method :rg_loaded_from,   :loaded_from

    def full_gem_path
      # this cannot check source.is_a?(Bundler::Plugin::API::Source)
      # because that _could_ trip the autoload, and if there are unresolved
      # gems at that time, this method could be called inside another require,
      # thus raising with that constant being undefined. Better to check a method
      if source.respond_to?(:path) || (source.respond_to?(:bundler_plugin_api_source?) && source.bundler_plugin_api_source?)
        Pathname.new(loaded_from).dirname.expand_path(source.root).to_s.tap{|x| x.untaint if RUBY_VERSION < "2.7" }
      else
        rg_full_gem_path
      end
    end

    def loaded_from
      if relative_loaded_from
        source.path.join(relative_loaded_from).to_s
      else
        rg_loaded_from
      end
    end

    def load_paths
      full_require_paths
    end

    alias_method :rg_extension_dir, :extension_dir
    def extension_dir
      @bundler_extension_dir ||= if source.respond_to?(:extension_dir_name)
        unique_extension_dir = [source.extension_dir_name, File.basename(full_gem_path)].uniq.join("-")
        File.expand_path(File.join(extensions_dir, unique_extension_dir))
      else
        rg_extension_dir
      end
    end

    remove_method :gem_dir if instance_methods(false).include?(:gem_dir)
    def gem_dir
      full_gem_path
    end

    def groups
      @groups ||= []
    end

    def git_version
      return unless loaded_from && source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    def to_gemfile(path = nil)
      gemfile = String.new("source 'https://rubygems.org'\n")
      gemfile << dependencies_to_gemfile(nondevelopment_dependencies)
      unless development_dependencies.empty?
        gemfile << "\n"
        gemfile << dependencies_to_gemfile(development_dependencies, :development)
      end
      gemfile
    end

    def nondevelopment_dependencies
      dependencies - development_dependencies
    end

    private

    def dependencies_to_gemfile(dependencies, group = nil)
      gemfile = String.new
      if dependencies.any?
        gemfile << "group :#{group} do\n" if group
        dependencies.each do |dependency|
          gemfile << "  " if group
          gemfile << %(gem "#{dependency.name}")
          req = dependency.requirements_list.first
          gemfile << %(, "#{req}") if req
          gemfile << "\n"
        end
        gemfile << "end\n" if group
      end
      gemfile
    end
  end

  class Dependency
    attr_accessor :source, :groups, :all_sources

    alias_method :eql?, :==

    def encode_with(coder)
      to_yaml_properties.each do |ivar|
        coder[ivar.to_s.sub(/^@/, "")] = instance_variable_get(ivar)
      end
    end

    def to_yaml_properties
      instance_variables.reject {|p| ["@source", "@groups", "@all_sources"].include?(p.to_s) }
    end

    def to_lock
      out = String.new("  #{name}")
      unless requirement.none?
        reqs = requirement.requirements.map {|o, v| "#{o} #{v}" }.sort.reverse
        out << " (#{reqs.join(", ")})"
      end
      out
    end
  end

  # comparison is done order independently since rubygems 3.2.0.rc.2
  unless Gem::Requirement.new("> 1", "< 2") == Gem::Requirement.new("< 2", "> 1")
    class Requirement
      module OrderIndependentComparison
        def ==(other)
          if _requirements_sorted? && other._requirements_sorted?
            super
          else
            _with_sorted_requirements == other._with_sorted_requirements
          end
        end

        protected

        def _requirements_sorted?
          return @_are_requirements_sorted if defined?(@_are_requirements_sorted)
          strings = as_list
          @_are_requirements_sorted = strings == strings.sort
        end

        def _with_sorted_requirements
          @_with_sorted_requirements ||= _requirements_sorted? ? self : self.class.new(as_list.sort)
        end
      end

      prepend OrderIndependentComparison
    end
  end

  if Gem::Requirement.new("~> 2.0").hash == Gem::Requirement.new("~> 2.0.0").hash
    class Requirement
      module CorrectHashForLambdaOperator
        def hash
          if requirements.any? {|r| r.first == "~>" }
            requirements.map {|r| r.first == "~>" ? [r[0], r[1].to_s] : r }.sort.hash
          else
            super
          end
        end
      end

      prepend CorrectHashForLambdaOperator
    end
  end

  class Platform
    JAVA  = Gem::Platform.new("java") unless defined?(JAVA)
    MSWIN = Gem::Platform.new("mswin32") unless defined?(MSWIN)
    MSWIN64 = Gem::Platform.new("mswin64") unless defined?(MSWIN64)
    MINGW = Gem::Platform.new("x86-mingw32") unless defined?(MINGW)
    X64_MINGW = Gem::Platform.new("x64-mingw32") unless defined?(X64_MINGW)

    undef_method :hash if method_defined? :hash
    def hash
      @cpu.hash ^ @os.hash ^ @version.hash
    end

    undef_method :eql? if method_defined? :eql?
    alias_method :eql?, :==
  end

  require "rubygems/util"

  Util.singleton_class.module_eval do
    if Util.singleton_methods.include?(:glob_files_in_dir) # since 3.0.0.beta.2
      remove_method :glob_files_in_dir
    end

    def glob_files_in_dir(glob, base_path)
      if RUBY_VERSION >= "2.5"
        Dir.glob(glob, :base => base_path).map! {|f| File.expand_path(f, base_path) }
      else
        Dir.glob(File.join(base_path.to_s.gsub(/[\[\]]/, '\\\\\\&'), glob)).map! {|f| File.expand_path(f) }
      end
    end
  end
end

module Gem
  class Specification
    include ::Bundler::MatchPlatform
  end
end
