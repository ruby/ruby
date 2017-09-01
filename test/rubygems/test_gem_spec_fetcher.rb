# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/spec_fetcher'

class TestGemSpecFetcher < Gem::TestCase

  def tuple(*args)
    Gem::NameTuple.new(*args)
  end

  def setup
    super

    @uri = URI.parse @gem_repo
    @source = Gem::Source.new(@uri)

    @sf = Gem::SpecFetcher.new
  end

  def test_initialize
    fetcher = Gem::SpecFetcher.new

    assert_same Gem.sources, fetcher.sources
  end

  def test_initialize_source
    alternate = 'http://alternate.example'
    fetcher = Gem::SpecFetcher.new alternate

    refute_same Gem.sources, fetcher.sources

    assert_equal alternate, fetcher.sources
  end

  def test_initialize_nonexistent_home_dir
    FileUtils.rmdir Gem.user_home

    assert Gem::SpecFetcher.new
  end

  def test_initialize_unwritable_home_dir
    skip 'chmod not supported' if Gem.win_platform?

    FileUtils.chmod 0000, Gem.user_home

    begin
      assert Gem::SpecFetcher.new
    ensure
      FileUtils.chmod 0755, Gem.user_home
    end
  end

  def test_spec_for_dependency_all
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
      fetcher.spec 'a', 2
      fetcher.spec 'a', '3.a'
    end

    dep = Gem::Dependency.new 'a', ">= 1"

    specs_and_sources, _ = @sf.spec_for_dependency dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    expected = [['a-1', @source], ['a-2', @source]]

    assert_equal expected, spec_names

    assert_same specs_and_sources.first.last, specs_and_sources.last.last
  end

  def test_spec_for_dependency_latest
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'a', '3.a'
    end

    dep = Gem::Dependency.new 'a'
    specs_and_sources, _ = @sf.spec_for_dependency dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [['a-2', Gem::Source.new(@gem_repo)]],
                 spec_names
  end

  def test_spec_for_dependency_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec 'a', '1.a'
      fetcher.spec 'a', 1
    end

    specs_and_sources, _ = @sf.spec_for_dependency dep('a', '1.a')

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [['a-1.a', Gem::Source.new(@gem_repo)]], spec_names
  end

  def test_spec_for_dependency_platform
    util_set_arch 'i386-linux'

    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    dep = Gem::Dependency.new 'pl', 1
    specs_and_sources, _ = @sf.spec_for_dependency dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [['pl-1-x86-linux', Gem::Source.new(@gem_repo)]],
                 spec_names
  end

  def test_spec_for_dependency_mismatched_platform
    util_set_arch 'hrpa-989'

    spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    dep = Gem::Dependency.new 'pl', 1
    specs_and_sources, errors = @sf.spec_for_dependency dep

    assert_equal 0, specs_and_sources.size
    assert_equal 1, errors.size
    pmm = errors.first

    assert_equal "i386-linux", pmm.platforms.first
    assert_equal "Found pl (1), but was for platform i386-linux", pmm.wordy
  end

  def test_spec_for_dependency_bad_fetch_spec
    src = Gem::Source.new(@gem_repo)
    def src.fetch_spec(name)
      raise Gem::RemoteFetcher::FetchError.new("bad news from the internet", @uri)
    end

    Gem.sources.replace [src]

    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
      fetcher.spec 'a', 2
      fetcher.spec 'a', '3.a'
    end

    dep = Gem::Dependency.new 'a', ">= 1"

    specs_and_sources, errors = @sf.spec_for_dependency dep

    assert_equal [], specs_and_sources
    sfp = errors.first

    assert_kind_of Gem::SourceFetchProblem, sfp
    assert_equal src, sfp.source
    assert_equal "bad news from the internet (#{@gem_repo})", sfp.error.message
  end

  def test_available_specs_latest
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'a', '3.a'
      fetcher.legacy_platform
    end

    specs, _ = @sf.available_specs(:latest)

    assert_equal [@source], specs.keys

    expected = Gem::NameTuple.from_list \
      [['a',      v(2),     Gem::Platform::RUBY],
       ['pl',     v(1),     'i386-linux']]

    assert_equal expected, specs[@source]
  end

  def test_available_specs_released
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.legacy_platform
    end

    specs, _ = @sf.available_specs(:released)

    assert_equal [@source], specs.keys

    expected = Gem::NameTuple.from_list \
      [['a',      v(1),     Gem::Platform::RUBY],
       ['pl',     v(1),     'i386-linux']]

    assert_equal expected, specs[@source]
  end

  def test_available_specs_complete
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
      fetcher.spec 'b', 2
      fetcher.legacy_platform
    end

    specs, _ = @sf.available_specs(:complete)

    assert_equal [@source], specs.keys

    expected = Gem::NameTuple.from_list \
      [['a',      v(1),     Gem::Platform::RUBY],
       ['a',      v('2.a'), Gem::Platform::RUBY],
       ['b',      v(2),     Gem::Platform::RUBY],
       ['pl',     v(1),     'i386-linux']]

    assert_equal expected, specs[@source]
  end

  def test_available_specs_complete_handles_no_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
      fetcher.spec 'b', 2
      fetcher.legacy_platform
    end

    v = Gem.marshal_version
    @fetcher.data.delete "#{@gem_repo}prerelease_specs.#{v}.gz"

    specs, _ = @sf.available_specs(:complete)

    assert_equal [@source], specs.keys

    expected = Gem::NameTuple.from_list \
      [['a',      v(1), Gem::Platform::RUBY],
       ['b',      v(2), Gem::Platform::RUBY],
       ['pl',     v(1), 'i386-linux']]

    assert_equal expected, specs[@source]
  end

  def test_available_specs_cache
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    specs, _ = @sf.available_specs(:latest)

    refute specs[@source].empty?

    @fetcher.data["#{@gem_repo}/latest_specs.#{Gem.marshal_version}.gz"] = nil

    cached_specs, _ = @sf.available_specs(:latest)

    assert_equal specs, cached_specs
  end

  def test_available_specs_cache_released
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
      fetcher.spec 'b', 2
      fetcher.legacy_platform
    end

    specs, _ = @sf.available_specs(:released)

    refute specs[@source].empty?

    @fetcher.data["#{@gem_repo}/specs.#{Gem.marshal_version}.gz"] = nil

    cached_specs, _ = @sf.available_specs(:released)

    assert_equal specs, cached_specs
  end

  def test_available_specs_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', '2.a'
    end

    specs, _ = @sf.available_specs(:prerelease)

    expected = Gem::NameTuple.from_list \
      [['a',  v('2.a'), Gem::Platform::RUBY]]

    assert_equal expected, specs[@source]
  end

  def test_available_specs_with_bad_source
    Gem.sources.replace ["http://not-there.nothing"]

    specs, errors = @sf.available_specs(:latest)

    assert_equal({}, specs)
    assert_kind_of Gem::SourceFetchProblem, errors.first
  end

end

