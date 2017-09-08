# frozen_string_literal: true
require "forwardable"
require "support/the_bundle"
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

    MAJOR_DEPRECATION = /^\[DEPRECATED FOR 2\.0\]\s*/

    RSpec::Matchers.define :lack_errors do
      diffable
      match do |actual|
        actual.gsub(/#{MAJOR_DEPRECATION}.+[\n]?/, "") == ""
      end
    end

    RSpec::Matchers.define :eq_err do |expected|
      diffable
      match do |actual|
        actual.gsub(/#{MAJOR_DEPRECATION}.+[\n]?/, "") == expected
      end
    end

    RSpec::Matchers.define :have_major_deprecation do |expected|
      diffable
      match do |actual|
        actual.split(MAJOR_DEPRECATION).any? do |d|
          !d.empty? && values_match?(expected, d.strip)
        end
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

    RSpec::Matchers.define :have_rubyopts do |*args|
      args = args.flatten
      args = args.first.split(/\s+/) if args.size == 1

      match do |actual|
        actual = actual.split(/\s+/) if actual.is_a?(String)
        args.all? {|arg| actual.include?(arg) } && actual.uniq.size == actual.size
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
        groups = Array(opts[:groups])
        groups << opts
        @errors = names.map do |name|
          name, version, platform = name.split(/\s+/)
          version_const = name == "bundler" ? "Bundler::VERSION" : Spec::Builders.constantize(name)
          begin
            run! "require '#{name}.rb'; puts #{version_const}", *groups
          rescue => e
            next "#{name} is not installed:\n#{indent(e)}"
          end
          out.gsub!(/#{MAJOR_DEPRECATION}.*$/, "")
          actual_version, actual_platform = out.strip.split(/\s+/, 2)
          unless Gem::Version.new(actual_version) == Gem::Version.new(version)
            next "#{name} was expected to be at version #{version} but was #{actual_version}"
          end
          unless actual_platform == platform
            next "#{name} was expected to be of platform #{platform} but was #{actual_platform}"
          end
          next unless source
          begin
            source_const = "#{Spec::Builders.constantize(name)}_SOURCE"
            run! "require '#{name}/source'; puts #{source_const}", *groups
          rescue
            next "#{name} does not have a source defined:\n#{indent(e)}"
          end
          out.gsub!(/#{MAJOR_DEPRECATION}.*$/, "")
          unless out.strip == source
            next "Expected #{name} (#{version}) to be installed from `#{source}`, was actually from `#{out}`"
          end
        end.compact

        @errors.empty?
      end

      match_when_negated do
        opts = names.last.is_a?(Hash) ? names.pop : {}
        groups = Array(opts[:groups]) || []
        @errors = names.map do |name|
          name, version = name.split(/\s+/, 2)
          begin
            run <<-R, *(groups + [opts])
              begin
                require '#{name}'
                puts #{Spec::Builders.constantize(name)}
              rescue LoadError, NameError
                puts "WIN"
              end
            R
          rescue => e
            next "checking for #{name} failed:\n#{e}"
          end
          next if out == "WIN"
          next "expected #{name} to not be installed, but it was" if version.nil?
          if Gem::Version.new(out) == Gem::Version.new(version)
            next "expected #{name} (#{version}) not to be installed, but it was"
          end
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
      expect(bundled_app("Gemfile.lock")).to read_as(strip_whitespace(expected))
    end
  end
end
