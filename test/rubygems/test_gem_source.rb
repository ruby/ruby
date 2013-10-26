require 'rubygems/test_case'
require 'rubygems/source'

class TestGemSource < Gem::TestCase

  def tuple(*args)
    Gem::NameTuple.new(*args)
  end

  def setup
    super

    util_setup_fake_fetcher

    @a_pre = new_spec 'a', '1.a'

    install_specs @a_pre

    @source = Gem::Source.new(@gem_repo)

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

    @released = Gem::NameTuple.from_list \
                 [["a",      Gem::Version.new("1"),   "ruby"],
                  ["a",      Gem::Version.new("2"),   "ruby"],
                  ["a_evil", Gem::Version.new("9"),   "ruby"],
                  ["c",      Gem::Version.new("1.2"), "ruby"],
                  ['dep_x',  Gem::Version.new(1),     'ruby'],
                  ["pl",     Gem::Version.new("1"),   "i386-linux"],
                  ['x',  Gem::Version.new(1),     'ruby']]
  end

  def test_api_uri
    assert_equal @source.api_uri, @source.uri
  end

  def test_api_uri_resolved_from_remote_fetcher
    uri = URI.parse "http://gem.example/foo"
    @fetcher.api_endpoints[uri] = URI.parse "http://api.blah"

    src = Gem::Source.new uri
    assert_equal URI.parse("http://api.blah"), src.api_uri
  end

  def test_cache_dir_escapes_windows_paths
    uri = URI.parse("file:///C:/WINDOWS/Temp/gem_repo")
    root = File.join Gem.user_home, '.gem', 'specs'
    cache_dir = @source.cache_dir(uri).gsub(root, '')
    assert cache_dir !~ /:/, "#{cache_dir} should not contain a :"
  end

  def test_fetch_spec
    spec_uri = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a1.spec_name}"
    @fetcher.data["#{spec_uri}.rz"] = util_zip(Marshal.dump(@a1))

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), 'ruby')
    assert_equal @a1.full_name, spec.full_name

    cache_dir = @source.cache_dir URI.parse(spec_uri)

    cache_file = File.join cache_dir, @a1.spec_name

    assert File.exist?(cache_file)
  end

  def test_fetch_spec_cached
    spec_uri = "#{@gem_repo}/#{Gem::MARSHAL_SPEC_DIR}#{@a1.spec_name}"
    @fetcher.data["#{spec_uri}.rz"] = nil

    cache_dir = @source.cache_dir URI.parse(spec_uri)
    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, @a1.spec_name

    open cache_file, 'wb' do |io|
      Marshal.dump @a1, io
    end

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), 'ruby')
    assert_equal @a1.full_name, spec.full_name
  end

  def test_fetch_spec_platform
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@pl1.original_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@pl1))

    spec = @source.fetch_spec tuple('pl', Gem::Version.new(1), 'i386-linux')

    assert_equal @pl1.full_name, spec.full_name
  end

  def test_fetch_spec_platform_ruby
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a1.spec_name}.rz"] =
      util_zip(Marshal.dump(@a1))

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), nil)
    assert_equal @a1.full_name, spec.full_name

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), '')
    assert_equal @a1.full_name, spec.full_name
  end

  def test_load_specs
    expected = @released
    assert_equal expected, @source.load_specs(:released)

    cache_dir = File.join Gem.user_home, '.gem', 'specs', 'gems.example.com%80'
    assert File.exist?(cache_dir), "#{cache_dir} does not exist"

    cache_file = File.join cache_dir, "specs.#{Gem.marshal_version}"
    assert File.exist?(cache_file)
  end

  def test_load_specs_cached
    # Make sure the cached version is actually different:
    @latest_specs << Gem::NameTuple.new('cached', Gem::Version.new('1.0.0'), 'ruby')

    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] = nil
    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}"] =
      ' ' * Marshal.dump(@latest_specs).length

    cache_dir = File.join Gem.user_home, '.gem', 'specs', 'gems.example.com%80'

    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, "latest_specs.#{Gem.marshal_version}"

    open cache_file, 'wb' do |io|
      Marshal.dump @latest_specs, io
    end

    latest_specs = @source.load_specs :latest

    assert_equal @latest_specs, latest_specs
  end

  def test_load_specs_cached_empty
    # Make sure the cached version is actually different:
    @latest_specs << Gem::NameTuple.new('fixed', Gem::Version.new('1.0.0'), 'ruby')
    # Setup valid data on the 'remote'
    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] =
          util_gzip(Marshal.dump(@latest_specs))

    cache_dir = File.join Gem.user_home, '.gem', 'specs', 'gems.example.com%80'

    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, "latest_specs.#{Gem.marshal_version}"

    open cache_file, 'wb' do |io|
      # Setup invalid data in the cache:
      io.write Marshal.dump(@latest_specs)[0, 10]
    end

    latest_specs = @source.load_specs :latest

    assert_equal @latest_specs, latest_specs
  end

  def test_load_specs_from_unavailable_uri
    src = Gem::Source.new("http://not-there.nothing")

    assert_raises Gem::RemoteFetcher::FetchError do
      src.load_specs :latest
    end
  end

  def test_update_cache_eh
    assert @source.update_cache?
  end

  def test_update_cache_eh_home_nonexistent
    FileUtils.rmdir Gem.user_home

    refute @source.update_cache?
  end

end

