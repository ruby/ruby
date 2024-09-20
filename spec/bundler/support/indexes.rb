# frozen_string_literal: true

module Spec
  module Indexes
    def dep(name, reqs = nil)
      @deps ||= []
      @deps << Bundler::Dependency.new(name, reqs)
    end

    def platform(*args)
      @platforms ||= []
      @platforms.concat args.map {|p| Gem::Platform.new(p) }
    end

    alias_method :platforms, :platform

    def resolve(args = [], dependency_api_available: true)
      @platforms ||= ["ruby"]
      default_source = instance_double("Bundler::Source::Rubygems", specs: @index, to_s: "locally install gems", dependency_api_available?: dependency_api_available)
      source_requirements = { default: default_source }
      base = args[0] || Bundler::SpecSet.new([])
      base.each {|ls| ls.source = default_source }
      gem_version_promoter = args[1] || Bundler::GemVersionPromoter.new
      originally_locked = args[2] || Bundler::SpecSet.new([])
      unlock = args[3] || []
      @deps.each do |d|
        name = d.name
        source_requirements[name] = d.source = default_source
      end
      packages = Bundler::Resolver::Base.new(source_requirements, @deps, base, @platforms, locked_specs: originally_locked, unlock: unlock)
      Bundler::Resolver.new(packages, gem_version_promoter).start
    end

    def should_not_resolve
      expect { resolve }.to raise_error(Bundler::GemNotFound)
    end

    def should_resolve_as(specs)
      got = resolve
      got = got.map(&:full_name).sort
      expect(got).to eq(specs.sort)
    end

    def should_resolve_without_dependency_api(specs)
      got = resolve(dependency_api_available: false)
      got = got.map(&:full_name).sort
      expect(got).to eq(specs.sort)
    end

    def should_resolve_and_include(specs, args = [])
      got = resolve(args)
      got = got.map(&:full_name).sort
      specs.each do |s|
        expect(got).to include(s)
      end
    end

    def gem(*args, &blk)
      build_spec(*args, &blk).first
    end

    def locked(*args)
      Bundler::SpecSet.new(args.map do |name, version|
        gem(name, version)
      end)
    end

    def should_conservative_resolve_and_include(opts, unlock, specs)
      # empty unlock means unlock all
      opts = Array(opts)
      search = Bundler::GemVersionPromoter.new.tap do |s|
        s.level = opts.first
        s.strict = opts.include?(:strict)
      end
      should_resolve_and_include specs, [@base, search, @locked, unlock]
    end

    def an_awesome_index
      build_index do
        gem "myrack", %w[0.8 0.9 0.9.1 0.9.2 1.0 1.1]
        gem "myrack-mount", %w[0.4 0.5 0.5.1 0.5.2 0.6]

        # --- Pre-release support
        gem "RubyGems\0", ["1.3.2"]

        # --- Rails
        versions "1.2.3 2.2.3 2.3.5 3.0.0.beta 3.0.0.beta1" do |version|
          gem "activesupport", version
          gem "actionpack", version do
            dep "activesupport", version
            if version >= v("3.0.0.beta")
              dep "myrack", "~> 1.1"
              dep "myrack-mount", ">= 0.5"
            elsif version > v("2.3")   then dep "myrack", "~> 1.0.0"
            elsif version > v("2.0.0") then dep "myrack", "~> 0.9.0"
            end
          end
          gem "activerecord", version do
            dep "activesupport", version
            dep "arel", ">= 0.2" if version >= v("3.0.0.beta")
          end
          gem "actionmailer", version do
            dep "activesupport", version
            dep "actionmailer",  version
          end
          if version < v("3.0.0.beta")
            gem "railties", version do
              dep "activerecord",  version
              dep "actionpack",    version
              dep "actionmailer",  version
              dep "activesupport", version
            end
          else
            gem "railties", version
            gem "rails", version do
              dep "activerecord",  version
              dep "actionpack",    version
              dep "actionmailer",  version
              dep "activesupport", version
              dep "railties",      version
            end
          end
        end

        versions "1.0 1.2 1.2.1 1.2.2 1.3 1.3.0.1 1.3.5 1.4.0 1.4.2 1.4.2.1" do |version|
          platforms "ruby java mswin32 mingw32 x64-mingw32" do |platform|
            next if version == v("1.4.2.1") && platform != pl("x86-mswin32")
            next if version == v("1.4.2") && platform == pl("x86-mswin32")
            gem "nokogiri", version, platform do
              dep "weakling", ">= 0.0.3" if platform =~ pl("java") # rubocop:disable Performance/RegexpMatch
            end
          end
        end

        versions "0.0.1 0.0.2 0.0.3" do |version|
          gem "weakling", version
        end

        # --- Rails related
        versions "1.2.3 2.2.3 2.3.5" do |version|
          gem "activemerchant", version do
            dep "activesupport", ">= #{version}"
          end
        end

        gem "reform", ["1.0.0"] do
          dep "activesupport", ">= 1.0.0.beta1"
        end

        gem "need-pre", ["1.0.0"] do
          dep "activesupport", "~> 3.0.0.beta1"
        end
      end
    end

    # Builder 3.1.4 will activate first, but if all
    # goes well, it should resolve to 3.0.4
    def a_conflict_index
      build_index do
        gem "builder", %w[3.0.4 3.1.4]
        gem("grape", "0.2.6") do
          dep "builder", ">= 0"
        end

        versions "3.2.8 3.2.9 3.2.10 3.2.11" do |version|
          gem("activemodel", version) do
            dep "builder", "~> 3.0.0"
          end
        end

        gem("my_app", "1.0.0") do
          dep "activemodel", ">= 0"
          dep "grape", ">= 0"
        end
      end
    end

    def a_complex_conflict_index
      build_index do
        gem("a", %w[1.0.2 1.1.4 1.2.0 1.4.0]) do
          dep "d", ">= 0"
        end

        gem("d", %w[1.3.0 1.4.1]) do
          dep "x", ">= 0"
        end

        gem "d", "0.9.8"

        gem("b", "0.3.4") do
          dep "a", ">= 1.5.0"
        end

        gem("b", "0.3.5") do
          dep "a", ">= 1.2"
        end

        gem("b", "0.3.3") do
          dep "a", "> 1.0"
        end

        versions "3.2 3.3" do |version|
          gem("c", version) do
            dep "a", "~> 1.0"
          end
        end

        gem("my_app", "1.3.0") do
          dep "c", ">= 4.0"
          dep "b", ">= 0"
        end

        gem("my_app", "1.2.0") do
          dep "c", "~> 3.3.0"
          dep "b", "0.3.4"
        end

        gem("my_app", "1.1.0") do
          dep "c", "~> 3.2.0"
          dep "b", "0.3.5"
        end
      end
    end

    def index_with_conflict_on_child
      build_index do
        gem "json", %w[1.6.5 1.7.7 1.8.0]

        gem("chef", "10.26") do
          dep "json", [">= 1.4.4", "<= 1.7.7"]
        end

        gem("berkshelf", "2.0.7") do
          dep "json", ">= 1.7.7"
        end

        gem("chef_app", "1.0.0") do
          dep "berkshelf", "~> 2.0"
          dep "chef", "~> 10.26"
        end
      end
    end

    # Issue #3459
    def a_complicated_index
      build_index do
        gem "foo", %w[3.0.0 3.0.5] do
          dep "qux", ["~> 3.1"]
          dep "baz", ["< 9.0", ">= 5.0"]
          dep "bar", ["~> 1.0"]
          dep "grault", ["~> 3.1"]
        end

        gem "foo", "1.2.1" do
          dep "baz", ["~> 4.2"]
          dep "bar", ["~> 1.0"]
          dep "qux", ["~> 3.1"]
          dep "grault", ["~> 2.0"]
        end

        gem "bar", "1.0.5" do
          dep "grault", ["~> 3.1"]
          dep "baz", ["< 9", ">= 4.2"]
        end

        gem "bar", "1.0.3" do
          dep "baz", ["< 9", ">= 4.2"]
          dep "grault", ["~> 2.0"]
        end

        gem "baz", "8.2.10" do
          dep "grault", ["~> 3.0"]
          dep "garply", [">= 0.5.1", "~> 0.5"]
        end

        gem "baz", "5.0.2" do
          dep "grault", ["~> 2.0"]
          dep "garply", [">= 0.3.1"]
        end

        gem "baz", "4.2.0" do
          dep "grault", ["~> 2.0"]
          dep "garply", [">= 0.3.1"]
        end

        gem "grault", %w[2.6.3 3.1.1]

        gem "garply", "0.5.1" do
          dep "waldo", ["~> 0.1.3"]
        end

        gem "waldo", "0.1.5" do
          dep "plugh", ["~> 0.6.0"]
        end

        gem "plugh", %w[0.6.3 0.6.11 0.7.0]

        gem "qux", "3.2.21" do
          dep "plugh", [">= 0.6.4", "~> 0.6"]
          dep "corge", ["~> 1.0"]
        end

        gem "corge", "1.10.1"
      end
    end

    def a_unresolvable_child_index
      build_index do
        gem "json", %w[1.8.0]

        gem("chef", "10.26") do
          dep "json", [">= 1.4.4", "<= 1.7.7"]
        end

        gem("berkshelf", "2.0.7") do
          dep "json", ">= 1.7.7"
        end

        gem("chef_app_error", "1.0.0") do
          dep "berkshelf", "~> 2.0"
          dep "chef", "~> 10.26"
        end
      end
    end

    def a_index_with_root_conflict_on_child
      build_index do
        gem "builder", %w[2.1.2 3.0.1 3.1.3]
        gem "i18n", %w[0.4.1 0.4.2]

        gem "activesupport", %w[3.0.0 3.0.1 3.0.5 3.1.7]

        gem("activemodel", "3.0.5") do
          dep "activesupport", "= 3.0.5"
          dep "builder", "~> 2.1.2"
          dep "i18n", "~> 0.4"
        end

        gem("activemodel", "3.0.0") do
          dep "activesupport", "= 3.0.0"
          dep "builder", "~> 2.1.2"
          dep "i18n", "~> 0.4.1"
        end

        gem("activemodel", "3.1.3") do
          dep "activesupport", "= 3.1.3"
          dep "builder", "~> 2.1.2"
          dep "i18n", "~> 0.5"
        end

        gem("activerecord", "3.0.0") do
          dep "activesupport", "= 3.0.0"
          dep "activemodel", "= 3.0.0"
        end

        gem("activerecord", "3.0.5") do
          dep "activesupport", "= 3.0.5"
          dep "activemodel", "= 3.0.5"
        end

        gem("activerecord", "3.0.9") do
          dep "activesupport", "= 3.1.5"
          dep "activemodel", "= 3.1.5"
        end
      end
    end

    def a_circular_index
      build_index do
        gem "myrack", "1.0.1"
        gem("foo", "0.2.6") do
          dep "bar", ">= 0"
        end

        gem("bar", "1.0.0") do
          dep "foo", ">= 0"
        end

        gem("circular_app", "1.0.0") do
          dep "foo", ">= 0"
          dep "bar", ">= 0"
        end
      end
    end

    def an_ambiguous_index
      build_index do
        gem("a", "1.0.0") do
          dep "c", ">= 0"
        end

        gem("b", %w[0.5.0 1.0.0])

        gem("b", "2.0.0") do
          dep "c", "< 2.0.0"
        end

        gem("c", "1.0.0") do
          dep "d", "1.0.0"
        end

        gem("c", "2.0.0") do
          dep "d", "2.0.0"
        end

        gem("d", %w[1.0.0 2.0.0])
      end
    end

    def optional_prereleases_index
      build_index do
        gem("a", %w[1.0.0])

        gem("a", "2.0.0") do
          dep "b", ">= 2.0.0.pre"
        end

        gem("b", %w[0.9.0 1.5.0 2.0.0.pre])

        # --- Pre-release support
        gem "RubyGems\0", ["1.3.2"]
      end
    end
  end
end
