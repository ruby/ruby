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

    util_setup_fake_fetcher

    @a_pre = new_spec 'a', '1.a'

    install_specs @a_pre

    Gem::Specification.remove_spec @b2

    all = Gem::Specification.map { |spec|
      Gem::NameTuple.new(spec.name, spec.version, spec.original_platform)
    }.sort

    @prerelease_specs, @specs = all.partition { |g| g.prerelease? }

    # TODO: couldn't all of this come from the fake spec fetcher?
    @latest_specs = Gem::Specification.latest_specs.sort.map { |spec|
      Gem::NameTuple.new(spec.name, spec.version, spec.original_platform)
    }

    v = Gem.marshal_version
    s_zip = util_gzip(Marshal.dump(Gem::NameTuple.to_basic(@specs)))
    l_zip = util_gzip(Marshal.dump(Gem::NameTuple.to_basic(@latest_specs)))
    p_zip = util_gzip(Marshal.dump(Gem::NameTuple.to_basic(@prerelease_specs)))
    @fetcher.data["#{@gem_repo}specs.#{v}.gz"]            = s_zip
    @fetcher.data["#{@gem_repo}latest_specs.#{v}.gz"]     = l_zip
    @fetcher.data["#{@gem_repo}prerelease_specs.#{v}.gz"] = p_zip

    @sf = Gem::SpecFetcher.new

    @released = Gem::NameTuple.from_list \
                 [["a",      Gem::Version.new("1"),   "ruby"],
                  ["a",      Gem::Version.new("2"),   "ruby"],
                  ["a_evil", Gem::Version.new("9"),   "ruby"],
                  ["c",      Gem::Version.new("1.2"), "ruby"],
                  ['dep_x',  Gem::Version.new(1),     'ruby'],
                  ["pl",     Gem::Version.new("1"),   "i386-linux"],
                  ['x',  Gem::Version.new(1),     'ruby']]
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
    d = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}"
    @fetcher.data["#{d}#{@a1.spec_name}.rz"]    = util_zip(Marshal.dump(@a1))
    @fetcher.data["#{d}#{@a2.spec_name}.rz"]    = util_zip(Marshal.dump(@a2))
    @fetcher.data["#{d}#{@a_pre.spec_name}.rz"] = util_zip(Marshal.dump(@a_pre))
    @fetcher.data["#{d}#{@a3a.spec_name}.rz"]   = util_zip(Marshal.dump(@a3a))

    dep = Gem::Dependency.new 'a', ">= 1"

    specs_and_sources, _ = @sf.spec_for_dependency dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    expected = [[@a1.full_name, @source], [@a2.full_name, @source]]

    assert_equal expected, spec_names

    assert_same specs_and_sources.first.last, specs_and_sources.last.last
  end

  def test_spec_for_dependency_latest
    d = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}"
    @fetcher.data["#{d}#{@a1.spec_name}.rz"]    = util_zip(Marshal.dump(@a1))
    @fetcher.data["#{d}#{@a2.spec_name}.rz"]    = util_zip(Marshal.dump(@a2))
    @fetcher.data["#{d}#{@a_pre.spec_name}.rz"] = util_zip(Marshal.dump(@a_pre))

    dep = Gem::Dependency.new 'a'
    specs_and_sources, _ = @sf.spec_for_dependency dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [[@a2.full_name, Gem::Source.new(@gem_repo)]], spec_names
  end

  def test_spec_for_dependency_prerelease
    d = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}"
    @fetcher.data["#{d}#{@a1.spec_name}.rz"]    = util_zip(Marshal.dump(@a1))
    @fetcher.data["#{d}#{@a2.spec_name}.rz"]    = util_zip(Marshal.dump(@a2))
    @fetcher.data["#{d}#{@a_pre.spec_name}.rz"] = util_zip(Marshal.dump(@a_pre))

    specs_and_sources, _ = @sf.spec_for_dependency dep('a', '1.a')

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [[@a_pre.full_name, Gem::Source.new(@gem_repo)]], spec_names
  end

  def test_spec_for_dependency_platform
    util_set_arch 'i386-linux'

    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@pl1.original_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@pl1))

    dep = Gem::Dependency.new 'pl', 1
    specs_and_sources, _ = @sf.spec_for_dependency dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [[@pl1.full_name, Gem::Source.new(@gem_repo)]], spec_names
  end

  def test_spec_for_dependency_mismatched_platform
    util_set_arch 'hrpa-989'

    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@pl1.original_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@pl1))

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

    d = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}"
    @fetcher.data["#{d}#{@a1.spec_name}.rz"]    = util_zip(Marshal.dump(@a1))
    @fetcher.data["#{d}#{@a2.spec_name}.rz"]    = util_zip(Marshal.dump(@a2))
    @fetcher.data["#{d}#{@a_pre.spec_name}.rz"] = util_zip(Marshal.dump(@a_pre))
    @fetcher.data["#{d}#{@a3a.spec_name}.rz"]   = util_zip(Marshal.dump(@a3a))

    dep = Gem::Dependency.new 'a', ">= 1"

    specs_and_sources, errors = @sf.spec_for_dependency dep

    assert_equal [], specs_and_sources
    sfp = errors.first

    assert_kind_of Gem::SourceFetchProblem, sfp
    assert_equal src, sfp.source
    assert_equal "bad news from the internet (#{@gem_repo})", sfp.error.message
  end

  def test_available_specs_latest
    specs, _ = @sf.available_specs(:latest)

    assert_equal [@source], specs.keys
    assert_equal @latest_specs, specs[@source].sort
  end

  def test_available_specs_released
    specs, _ = @sf.available_specs(:released)

    assert_equal [@source], specs.keys

    assert_equal @released, specs[@source].sort
  end

  def test_available_specs_complete
    specs, _ = @sf.available_specs(:complete)

    assert_equal [@source], specs.keys

    comp = @prerelease_specs + @released

    assert_equal comp.sort, specs[@source].sort
  end

  def test_available_specs_complete_handles_no_prerelease
    v = Gem.marshal_version
    @fetcher.data.delete "#{@gem_repo}prerelease_specs.#{v}.gz"

    specs, _ = @sf.available_specs(:complete)

    assert_equal [@source], specs.keys

    comp = @released

    assert_equal comp.sort, specs[@source].sort
  end


  def test_available_specs_cache
    specs, _ = @sf.available_specs(:latest)

    refute specs[@source].empty?

    @fetcher.data["#{@gem_repo}/latest_specs.#{Gem.marshal_version}.gz"] = nil

    cached_specs, _ = @sf.available_specs(:latest)

    assert_equal specs, cached_specs
  end

  def test_available_specs_cache_released
    specs, _ = @sf.available_specs(:released)

    refute specs[@source].empty?

    @fetcher.data["#{@gem_repo}/specs.#{Gem.marshal_version}.gz"] = nil

    cached_specs, _ = @sf.available_specs(:released)

    assert_equal specs, cached_specs
  end

  def test_available_specs_prerelease
    specs, _ = @sf.available_specs(:prerelease)

    assert_equal @prerelease_specs, specs[@source].sort
  end

  def test_available_specs_with_bad_source
    Gem.sources.replace ["http://not-there.nothing"]

    specs, errors = @sf.available_specs(:latest)

    assert_equal({}, specs)
    assert_kind_of Gem::SourceFetchProblem, errors.first
  end

end

