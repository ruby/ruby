# frozen_string_literal: true

RSpec.describe "Resolving" do
  before :each do
    @index = an_awesome_index
  end

  it "resolves a single gem" do
    dep "rack"

    should_resolve_as %w[rack-1.1]
  end

  it "resolves a gem with dependencies" do
    dep "actionpack"

    should_resolve_as %w[actionpack-2.3.5 activesupport-2.3.5 rack-1.0]
  end

  it "resolves a conflicting index" do
    @index = a_conflict_index
    dep "my_app"
    should_resolve_as %w[activemodel-3.2.11 builder-3.0.4 grape-0.2.6 my_app-1.0.0]
  end

  it "resolves a complex conflicting index" do
    @index = a_complex_conflict_index
    dep "my_app"
    should_resolve_as %w[a-1.4.0 b-0.3.5 c-3.2 d-0.9.8 my_app-1.1.0]
  end

  it "resolves a index with conflict on child" do
    @index = index_with_conflict_on_child
    dep "chef_app"
    should_resolve_as %w[berkshelf-2.0.7 chef-10.26 chef_app-1.0.0 json-1.7.7]
  end

  it "prefers explicitly requested dependencies when resolving an index which would otherwise be ambiguous" do
    @index = an_ambiguous_index
    dep "a"
    dep "b"
    should_resolve_as %w[a-1.0.0 b-2.0.0 c-1.0.0 d-1.0.0]
  end

  it "prefers non-prerelease resolutions in sort order" do
    @index = optional_prereleases_index
    dep "a"
    dep "b"
    should_resolve_as %w[a-1.0.0 b-1.5.0]
  end

  it "resolves a index with root level conflict on child" do
    @index = a_index_with_root_conflict_on_child
    dep "i18n", "~> 0.4"
    dep "activesupport", "~> 3.0"
    dep "activerecord", "~> 3.0"
    dep "builder", "~> 2.1.2"
    should_resolve_as %w[activesupport-3.0.5 i18n-0.4.2 builder-2.1.2 activerecord-3.0.5 activemodel-3.0.5]
  end

  it "resolves a gem specified with a pre-release version" do
    dep "activesupport", "~> 3.0.0.beta"
    dep "activemerchant"
    should_resolve_as %w[activemerchant-2.3.5 activesupport-3.0.0.beta1]
  end

  it "doesn't select a pre-release if not specified in the Gemfile" do
    dep "activesupport"
    dep "reform"
    should_resolve_as %w[reform-1.0.0 activesupport-2.3.5]
  end

  it "doesn't select a pre-release for sub-dependencies" do
    dep "reform"
    should_resolve_as %w[reform-1.0.0 activesupport-2.3.5]
  end

  it "selects a pre-release for sub-dependencies if it's the only option" do
    dep "need-pre"
    should_resolve_as %w[need-pre-1.0.0 activesupport-3.0.0.beta1]
  end

  it "selects a pre-release if it's specified in the Gemfile" do
    dep "activesupport", "= 3.0.0.beta"
    dep "actionpack"

    should_resolve_as %w[activesupport-3.0.0.beta actionpack-3.0.0.beta rack-1.1 rack-mount-0.6]
  end

  it "prefers non-pre-releases when doing conservative updates" do
    @index = build_index do
      gem "mail", "2.7.0"
      gem "mail", "2.7.1.rc1"
      gem "RubyGems\0", Gem::VERSION
    end
    dep "mail"
    @locked = locked ["mail", "2.7.0"]
    @base = locked
    should_conservative_resolve_and_include [:patch], [], ["mail-2.7.0"]
  end

  it "raises an exception if a child dependency is not resolved" do
    @index = a_unresolvable_child_index
    dep "chef_app_error"
    expect do
      resolve
    end.to raise_error(Bundler::SolveFailure)
  end

  it "raises an exception with the minimal set of conflicting dependencies" do
    @index = build_index do
      %w[0.9 1.0 2.0].each {|v| gem("a", v) }
      gem("b", "1.0") { dep "a", ">= 2" }
      gem("c", "1.0") { dep "a", "< 1" }
    end
    dep "a"
    dep "b"
    dep "c"
    expect do
      resolve
    end.to raise_error(Bundler::SolveFailure, <<~E.strip)
      Could not find compatible versions

      Because every version of c depends on a < 1
        and every version of b depends on a >= 2,
        every version of c is incompatible with b >= 0.
      So, because Gemfile depends on b >= 0
        and Gemfile depends on c >= 0,
        version solving has failed.
    E
  end

  it "should throw error in case of circular dependencies" do
    @index = a_circular_index
    dep "circular_app"

    expect do
      Bundler::SpecSet.new(resolve).sort
    end.to raise_error(Bundler::CyclicDependencyError, /please remove either gem 'bar' or gem 'foo'/i)
  end

  # Issue #3459
  it "should install the latest possible version of a direct requirement with no constraints given" do
    @index = a_complicated_index
    dep "foo"
    should_resolve_and_include %w[foo-3.0.5]
  end

  # Issue #3459
  it "should install the latest possible version of a direct requirement with constraints given" do
    @index = a_complicated_index
    dep "foo", ">= 3.0.0"
    should_resolve_and_include %w[foo-3.0.5]
  end

  it "takes into account required_ruby_version" do
    @index = build_index do
      gem "foo", "1.0.0" do
        dep "bar", ">= 0"
      end

      gem "foo", "2.0.0" do |s|
        dep "bar", ">= 0"
        s.required_ruby_version = "~> 2.0.0"
      end

      gem "bar", "1.0.0"

      gem "bar", "2.0.0" do |s|
        s.required_ruby_version = "~> 2.0.0"
      end

      gem "Ruby\0", "1.8.7"
    end
    dep "foo"
    dep "Ruby\0", "1.8.7"

    should_resolve_and_include %w[foo-1.0.0 bar-1.0.0]
  end

  context "conservative" do
    before :each do
      @index = build_index do
        gem("foo", "1.3.7") { dep "bar", "~> 2.0" }
        gem("foo", "1.3.8") { dep "bar", "~> 2.0" }
        gem("foo", "1.4.3") { dep "bar", "~> 2.0" }
        gem("foo", "1.4.4") { dep "bar", "~> 2.0" }
        gem("foo", "1.4.5") { dep "bar", "~> 2.1" }
        gem("foo", "1.5.0") { dep "bar", "~> 2.1" }
        gem("foo", "1.5.1") { dep "bar", "~> 3.0" }
        gem("foo", "2.0.0") { dep "bar", "~> 3.0" }
        gem "bar", %w[2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 3.0.0]
      end
      dep "foo"

      # base represents declared dependencies in the Gemfile that are still satisfied by the lockfile
      @base = Bundler::SpecSet.new([])

      # locked represents versions in lockfile
      @locked = locked(%w[foo 1.4.3], %w[bar 2.0.3])
    end

    it "resolves all gems to latest patch" do
      # strict is not set, so bar goes up a minor version due to dependency from foo 1.4.5
      should_conservative_resolve_and_include :patch, [], %w[foo-1.4.5 bar-2.1.1]
    end

    it "resolves all gems to latest patch strict" do
      # strict is set, so foo can only go up to 1.4.4 to avoid bar going up a minor version, and bar can go up to 2.0.5
      should_conservative_resolve_and_include [:patch, :strict], [], %w[foo-1.4.4 bar-2.0.5]
    end

    it "resolves foo only to latest patch - same dependency case" do
      @locked = locked(%w[foo 1.3.7], %w[bar 2.0.3])
      # bar is locked, and the lock holds here because the dependency on bar doesn't change on the matching foo version.
      should_conservative_resolve_and_include :patch, ["foo"], %w[foo-1.3.8 bar-2.0.3]
    end

    it "resolves foo only to latest patch - changing dependency not declared case" do
      # foo is the only gem being requested for update, therefore bar is locked, but bar is NOT
      # declared as a dependency in the Gemfile. In this case, locks don't apply to _changing_
      # dependencies and since the dependency of the selected foo gem changes, the latest matching
      # dependency of "bar", "~> 2.1" -- bar-2.1.1 -- is selected. This is not a bug and follows
      # the long-standing documented Conservative Updating behavior of bundle install.
      # https://bundler.io/v1.12/man/bundle-install.1.html#CONSERVATIVE-UPDATING
      should_conservative_resolve_and_include :patch, ["foo"], %w[foo-1.4.5 bar-2.1.1]
    end

    it "resolves foo only to latest patch - changing dependency declared case" do
      # bar is locked AND a declared dependency in the Gemfile, so it will not move, and therefore
      # foo can only move up to 1.4.4.
      @base << build_spec("bar", "2.0.3").first
      should_conservative_resolve_and_include :patch, ["foo"], %w[foo-1.4.4 bar-2.0.3]
    end

    it "resolves foo only to latest patch strict" do
      # adding strict helps solve the possibly unexpected behavior of bar changing in the prior test case,
      # because no versions will be returned for bar ~> 2.1, so the engine falls back to ~> 2.0 (turn on
      # debugging to see this happen).
      should_conservative_resolve_and_include [:patch, :strict], ["foo"], %w[foo-1.4.4 bar-2.0.3]
    end

    it "resolves bar only to latest patch" do
      # bar is locked, so foo can only go up to 1.4.4
      should_conservative_resolve_and_include :patch, ["bar"], %w[foo-1.4.3 bar-2.0.5]
    end

    it "resolves all gems to latest minor" do
      # strict is not set, so bar goes up a major version due to dependency from foo 1.4.5
      should_conservative_resolve_and_include :minor, [], %w[foo-1.5.1 bar-3.0.0]
    end

    it "resolves all gems to latest minor strict" do
      # strict is set, so foo can only go up to 1.5.0 to avoid bar going up a major version
      should_conservative_resolve_and_include [:minor, :strict], [], %w[foo-1.5.0 bar-2.1.1]
    end

    it "resolves all gems to latest major" do
      should_conservative_resolve_and_include :major, [], %w[foo-2.0.0 bar-3.0.0]
    end

    it "resolves all gems to latest major strict" do
      should_conservative_resolve_and_include [:major, :strict], [], %w[foo-2.0.0 bar-3.0.0]
    end

    # Why would this happen in real life? If bar 2.2 has a bug that the author of foo wants to bypass
    # by reverting the dependency, the author of foo could release a new gem with an older requirement.
    context "revert to previous" do
      before :each do
        @index = build_index do
          gem("foo", "1.4.3") { dep "bar", "~> 2.2" }
          gem("foo", "1.4.4") { dep "bar", "~> 2.1.0" }
          gem("foo", "1.5.0") { dep "bar", "~> 2.0.0" }
          gem "bar", %w[2.0.5 2.1.1 2.2.3]
        end
        dep "foo"

        # base represents declared dependencies in the Gemfile that are still satisfied by the lockfile
        @base = Bundler::SpecSet.new([])

        # locked represents versions in lockfile
        @locked = locked(%w[foo 1.4.3], %w[bar 2.2.3])
      end

      it "could revert to a previous version level patch" do
        should_conservative_resolve_and_include :patch, [], %w[foo-1.4.4 bar-2.1.1]
      end

      it "cannot revert to a previous version in strict mode level patch" do
        # fall back to the locked resolution since strict means we can't regress either version
        should_conservative_resolve_and_include [:patch, :strict], [], %w[foo-1.4.3 bar-2.2.3]
      end

      it "could revert to a previous version level minor" do
        should_conservative_resolve_and_include :minor, [], %w[foo-1.5.0 bar-2.0.5]
      end

      it "cannot revert to a previous version in strict mode level minor" do
        # fall back to the locked resolution since strict means we can't regress either version
        should_conservative_resolve_and_include [:minor, :strict], [], %w[foo-1.4.3 bar-2.2.3]
      end
    end
  end

  it "handles versions that redundantly depend on themselves" do
    @index = build_index do
      gem "rack", "3.0.0"

      gem "standalone_migrations", "7.1.0" do
        dep "rack", "~> 2.0"
      end

      gem "standalone_migrations", "2.0.4" do
        dep "standalone_migrations", ">= 0"
      end

      gem "standalone_migrations", "1.0.13" do
        dep "rack", ">= 0"
      end
    end

    dep "rack", "~> 3.0"
    dep "standalone_migrations"

    should_resolve_as %w[rack-3.0.0 standalone_migrations-2.0.4]
  end

  it "ignores versions that incorrectly depend on themselves" do
    @index = build_index do
      gem "rack", "3.0.0"

      gem "standalone_migrations", "7.1.0" do
        dep "rack", "~> 2.0"
      end

      gem "standalone_migrations", "2.0.4" do
        dep "standalone_migrations", ">= 2.0.5"
      end

      gem "standalone_migrations", "1.0.13" do
        dep "rack", ">= 0"
      end
    end

    dep "rack", "~> 3.0"
    dep "standalone_migrations"

    should_resolve_as %w[rack-3.0.0 standalone_migrations-1.0.13]
  end

  it "does not ignore versions that incorrectly depend on themselves when dependency_api is not available" do
    @index = build_index do
      gem "rack", "3.0.0"

      gem "standalone_migrations", "7.1.0" do
        dep "rack", "~> 2.0"
      end

      gem "standalone_migrations", "2.0.4" do
        dep "standalone_migrations", ">= 2.0.5"
      end

      gem "standalone_migrations", "1.0.13" do
        dep "rack", ">= 0"
      end
    end

    dep "rack", "~> 3.0"
    dep "standalone_migrations"

    should_resolve_without_dependency_api %w[rack-3.0.0 standalone_migrations-2.0.4]
  end
end
