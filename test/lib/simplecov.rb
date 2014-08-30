#
# Code coverage for ruby 1.9. Please check out README for a full introduction.
#
module SimpleCov
  class << self
    attr_accessor :running

    #
    # Sets up SimpleCov to run against your project.
    # You can optionally specify a profile to use as well as configuration with a block:
    #   SimpleCov.start
    #    OR
    #   SimpleCov.start 'rails' # using rails profile
    #    OR
    #   SimpleCov.start do
    #     add_filter 'test'
    #   end
    #     OR
    #   SimpleCov.start 'rails' do
    #     add_filter 'test'
    #   end
    #
    # Please check out the RDoc for SimpleCov::Configuration to find about available config options
    #
    def start(profile=nil, &block)
      if SimpleCov.usable?
        load_profile(profile) if profile
        configure(&block) if block_given?
        @result = nil
        self.running = true
        Coverage.start
      else
        warn "WARNING: SimpleCov is activated, but you're not running Ruby 1.9+ - no coverage analysis will happen"
        warn "Starting with SimpleCov 1.0.0, even no-op compatibility with Ruby <= 1.8 will be entirely dropped."
        false
      end
    end

    #
    # Returns the result for the current coverage run, merging it across test suites
    # from cache using SimpleCov::ResultMerger if use_merging is activated (default)
    #
    def result
      @result ||= SimpleCov::Result.new(Coverage.result) if running
      # If we're using merging of results, store the current result
      # first, then merge the results and return those
      if use_merging
        SimpleCov::ResultMerger.store_result(@result) if @result
        return SimpleCov::ResultMerger.merged_result
      else
        return @result if defined? @result
      end
    ensure
      self.running = false
    end

    #
    # Returns nil if the result has not been computed
    # Otherwise, returns the result
    #
    def result?
      defined? @result and @result
    end

    #
    # Applies the configured filters to the given array of SimpleCov::SourceFile items
    #
    def filtered(files)
      result = files.clone
      filters.each do |filter|
        result = result.reject {|source_file| filter.matches?(source_file) }
      end
      SimpleCov::FileList.new result
    end

    #
    # Applies the configured groups to the given array of SimpleCov::SourceFile items
    #
    def grouped(files)
      grouped = {}
      grouped_files = []
      groups.each do |name, filter|
        grouped[name] = SimpleCov::FileList.new(files.select {|source_file| filter.matches?(source_file)})
        grouped_files += grouped[name]
      end
      if groups.length > 0 and (other_files = files.reject {|source_file| grouped_files.include?(source_file)}).length > 0
        grouped["Ungrouped"] = SimpleCov::FileList.new(other_files)
      end
      grouped
    end

    #
    # Applies the profile of given name on SimpleCov configuration
    #
    def load_profile(name)
      profiles.load(name)
    end

    def load_adapter(name)
      warn "method load_adapter is deprecated. use load_profile instead"
      load_profile(name)
    end

    #
    # Checks whether we're on a proper version of Ruby (likely 1.9+) which
    # provides coverage support
    #
    def usable?
      return @usable if defined? @usable and !@usable.nil?

      @usable = begin
        require 'coverage'
        require 'simplecov/jruby_fix'
        true
      rescue LoadError
        false
      end
    end
  end
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__)))
require 'simplecov/configuration'
SimpleCov.send :extend, SimpleCov::Configuration
require 'simplecov/exit_codes'
require 'simplecov/json'
require 'simplecov/profiles'
require 'simplecov/source_file'
require 'simplecov/file_list'
require 'simplecov/result'
require 'simplecov/filter'
require 'simplecov/formatter'
require 'simplecov/last_run'
require 'simplecov/merge_helpers'
require 'simplecov/result_merger'
require 'simplecov/command_guesser'
require 'simplecov/version'

# Load default config
require 'simplecov/defaults' unless ENV['SIMPLECOV_NO_DEFAULTS']

# Load Rails integration (only for Rails 3, see #113)
require 'simplecov/railtie' if defined? Rails::Railtie
