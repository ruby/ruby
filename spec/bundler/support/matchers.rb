# frozen_string_literal: true

require "forwardable"
require_relative "the_bundle"

module Spec
  module Matchers
    extend RSpec::Matchers

    class Precondition
      include RSpec::Matchers::Composable
      extend Forwardable
      def_delegators :failing_matcher,
        :failure_message,
        :actual,
        :description,
        :diffable?,
        :expected,
        :failure_message_when_negated

      def initialize(matcher, preconditions)
        @matcher = with_matchers_cloned(matcher)
        @preconditions = with_matchers_cloned(preconditions)
        @failure_index = nil
      end

      def matches?(target, &blk)
        return false if @failure_index = @preconditions.index {|pc| !pc.matches?(target, &blk) }
        @matcher.matches?(target, &blk)
      end

      def does_not_match?(target, &blk)
        return false if @failure_index = @preconditions.index {|pc| !pc.matches?(target, &blk) }
        if @matcher.respond_to?(:does_not_match?)
          @matcher.does_not_match?(target, &blk)
        else
          !@matcher.matches?(target, &blk)
        end
      end

      def expects_call_stack_jump?
        @matcher.expects_call_stack_jump? || @preconditions.any?(&:expects_call_stack_jump)
      end

      def supports_block_expectations?
        @matcher.supports_block_expectations? || @preconditions.any?(&:supports_block_expectations)
      end

      def failing_matcher
        @failure_index ? @preconditions[@failure_index] : @matcher
      end
    end

    def self.define_compound_matcher(matcher, preconditions, &declarations)
      raise "Must have preconditions to define a compound matcher" if preconditions.empty?
      define_method(matcher) do |*expected, &block_arg|
        Precondition.new(
          RSpec::Matchers::DSL::Matcher.new(matcher, declarations, self, *expected, &block_arg),
          preconditions
        )
      end
    end

    RSpec::Matchers.define :have_dep do |*args|
      dep = Bundler::Dependency.new(*args)

      match do |actual|
        actual.length == 1 && actual.all? {|d| d == dep }
      end
    end

    RSpec::Matchers.define :have_gem do |*args|
      match do |actual|
        actual.length == args.length && actual.all? {|a| args.include?(a.full_name) }
      end
    end

    RSpec::Matchers.define :be_sorted do
      diffable
      attr_reader :expected
      match do |actual|
        expected = block_arg ? actual.sort_by(&block_arg) : actual.sort
        actual.==(expected).tap do
          # HACK: since rspec won't show a diff when everything is a string
          differ = RSpec::Support::Differ.new
          @actual = differ.send(:object_to_string, actual)
          @expected = differ.send(:object_to_string, expected)
        end
      end
    end

    RSpec::Matchers.define :be_well_formed do
      match(&:empty?)

      failure_message do |actual|
        actual.join("\n")
      end
    end

    define_compound_matcher :read_as, [exist] do |file_contents|
      diffable

      match do |actual|
        @actual = Bundler.read_file(actual)
        values_match?(file_contents, @actual)
      end
    end

    def indent(string, padding = 4, indent_character = " ")
      string.to_s.gsub(/^/, indent_character * padding).gsub("\t", "    ")
    end

    define_compound_matcher :include_gems, [be_an_instance_of(Spec::TheBundle)] do |*names|
      match do
        opts = names.last.is_a?(Hash) ? names.pop : {}
        source = opts.delete(:source)
        groups = Array(opts.delete(:groups)).map(&:inspect).join(", ")
        opts[:raise_on_error] = false
        @errors = names.map do |full_name|
          name, version, platform = full_name.split(/\s+/)
          require_path = name.tr("-", "/")
          version_const = name == "bundler" ? "Bundler::VERSION" : Spec::Builders.constantize(name)
          source_const = "#{Spec::Builders.constantize(name)}_SOURCE"
          ruby <<~R, opts
            require 'bundler'
            Bundler.setup(#{groups})

            require '#{require_path}'
            actual_version, actual_platform = #{version_const}.split(/\s+/, 2)
            unless Gem::Version.new(actual_version) == Gem::Version.new('#{version}')
              puts actual_version
              exit 64
            end
            unless actual_platform.to_s == '#{platform}'
              puts actual_platform
              exit 65
            end
            require '#{require_path}/source'
            exit 0 if #{source.nil?}
            actual_source = #{source_const}
            unless actual_source == '#{source}'
              puts actual_source
              exit 66
            end
          R
          next if exitstatus == 0
          if exitstatus == 64
            actual_version = out.split("\n").last
            next "#{name} was expected to be at version #{version} but was #{actual_version}"
          end
          if exitstatus == 65
            actual_platform = out.split("\n").last
            next "#{name} was expected to be of platform #{platform} but was #{actual_platform}"
          end
          if exitstatus == 66
            actual_source = out.split("\n").last
            next "Expected #{name} (#{version}) to be installed from `#{source}`, was actually from `#{actual_source}`"
          end
          next "Command to check for inclusion of gem #{full_name} failed"
        end.compact

        @errors.empty?
      end

      match_when_negated do
        opts = names.last.is_a?(Hash) ? names.pop : {}
        groups = Array(opts.delete(:groups)).map(&:inspect).join(", ")
        opts[:raise_on_error] = false
        @errors = names.map do |name|
          name, version = name.split(/\s+/, 2)
          ruby <<-R, opts
            begin
              require 'bundler'
              Bundler.setup(#{groups})
            rescue Bundler::GemNotFound, Bundler::GitError
              exit 0
            end

            begin
              require '#{name}'
              name_constant = '#{Spec::Builders.constantize(name)}'
              if #{version.nil?} || name_constant == '#{version}'
                exit 64
              else
                exit 0
              end
            rescue LoadError, NameError
              exit 0
            end
          R
          next if exitstatus == 0
          next "command to check version of #{name} installed failed" unless exitstatus == 64
          next "expected #{name} to not be installed, but it was" if version.nil?
          next "expected #{name} (#{version}) not to be installed, but it was"
        end.compact

        @errors.empty?
      end

      failure_message do
        super() + " but:\n" + @errors.map {|e| indent(e) }.join("\n")
      end

      failure_message_when_negated do
        super() + " but:\n" + @errors.map {|e| indent(e) }.join("\n")
      end
    end
    RSpec::Matchers.define_negated_matcher :not_include_gems, :include_gems
    RSpec::Matchers.alias_matcher :include_gem, :include_gems

    def have_lockfile(expected)
      read_as(strip_whitespace(expected))
    end

    def plugin_should_be_installed(*names)
      names.each do |name|
        expect(Bundler::Plugin).to be_installed(name)
        path = Pathname.new(Bundler::Plugin.installed?(name))
        expect(path + "plugins.rb").to exist
      end
    end

    def plugin_should_not_be_installed(*names)
      names.each do |name|
        expect(Bundler::Plugin).not_to be_installed(name)
      end
    end

    def lockfile_should_be(expected)
      expect(bundled_app_lock).to have_lockfile(expected)
    end

    def gemfile_should_be(expected)
      expect(bundled_app_gemfile).to read_as(strip_whitespace(expected))
    end
  end
end
