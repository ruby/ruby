require 'rubygems/test_case'
require 'rubygems/source'

class TestGemSource < Gem::TestCase

  def tuple(*args)
    Gem::NameTuple.new(*args)
  end

  def setup
    super

    @specs = spec_fetcher do |fetcher|
      fetcher.spec 'a', '1.a'
      fetcher.gem  'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'b', 2
    end

    @source = Gem::Source.new(@gem_repo)
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
    root = Gem.spec_cache_dir
    cache_dir = @source.cache_dir(uri).gsub(root, '')
    assert cache_dir !~ /:/, "#{cache_dir} should not contain a :"
  end

  def test_dependency_resolver_set_bundler_api
    @fetcher.data["#{@gem_repo}api/v1/dependencies"] = 'data'

    set = @source.dependency_resolver_set

    assert_kind_of Gem::DependencyResolver::APISet, set
  end

  def test_dependency_resolver_set_marshal_api
    set = @source.dependency_resolver_set

    assert_kind_of Gem::DependencyResolver::IndexSet, set
  end

  def test_fetch_spec
    a1 = @specs['a-1']

    spec_uri = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{a1.spec_name}"

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), 'ruby')
    assert_equal a1.full_name, spec.full_name

    cache_dir = @source.cache_dir URI.parse(spec_uri)

    cache_file = File.join cache_dir, a1.spec_name

    assert File.exist?(cache_file)
  end

  def test_fetch_spec_cached
    a1 = @specs['a-1']

    spec_uri = "#{@gem_repo}/#{Gem::MARSHAL_SPEC_DIR}#{a1.spec_name}"
    @fetcher.data["#{spec_uri}.rz"] = nil

    cache_dir = @source.cache_dir URI.parse(spec_uri)
    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, a1.spec_name

    open cache_file, 'wb' do |io|
      Marshal.dump a1, io
    end

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), 'ruby')
    assert_equal a1.full_name, spec.full_name
  end

  def test_fetch_spec_platform
    specs = spec_fetcher do |fetcher|
      fetcher.legacy_platform
    end

    spec = @source.fetch_spec tuple('pl', Gem::Version.new(1), 'i386-linux')

    assert_equal specs['pl-1-x86-linux'].full_name, spec.full_name
  end

  def test_fetch_spec_platform_ruby
    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), nil)
    assert_equal @specs['a-1'].full_name, spec.full_name

    spec = @source.fetch_spec tuple('a', Gem::Version.new(1), '')
    assert_equal @specs['a-1'].full_name, spec.full_name
  end

  def test_load_specs
    released = @source.load_specs(:released).map { |spec| spec.full_name }
    assert_equal %W[a-2 a-1 b-2], released

    cache_dir = File.join Gem.spec_cache_dir, 'gems.example.com%80'
    assert File.exist?(cache_dir), "#{cache_dir} does not exist"

    cache_file = File.join cache_dir, "specs.#{Gem.marshal_version}"
    assert File.exist?(cache_file)
  end

  def test_load_specs_cached
    latest_specs = @source.load_specs :latest

    # Make sure the cached version is actually different:
    latest_specs << Gem::NameTuple.new('cached', Gem::Version.new('1.0.0'), 'ruby')

    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] = nil
    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}"] =
      ' ' * Marshal.dump(latest_specs).length

    cache_dir = File.join Gem.spec_cache_dir, 'gems.example.com%80'

    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, "latest_specs.#{Gem.marshal_version}"

    open cache_file, 'wb' do |io|
      Marshal.dump latest_specs, io
    end

    cached_specs = @source.load_specs :latest

    assert_equal latest_specs, cached_specs
  end

  def test_load_specs_cached_empty
    latest_specs = @source.load_specs :latest

    # Make sure the cached version is actually different:
    latest_specs << Gem::NameTuple.new('fixed', Gem::Version.new('1.0.0'), 'ruby')
    # Setup valid data on the 'remote'
    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] =
          util_gzip(Marshal.dump(latest_specs))

    cache_dir = File.join Gem.spec_cache_dir, 'gems.example.com%80'

    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, "latest_specs.#{Gem.marshal_version}"

    open cache_file, 'wb' do |io|
      # Setup invalid data in the cache:
      io.write Marshal.dump(latest_specs)[0, 10]
    end

    fixed_specs = @source.load_specs :latest

    assert_equal latest_specs, fixed_specs
  end

  def test_load_specs_from_unavailable_uri
    src = Gem::Source.new("http://not-there.nothing")

    assert_raises Gem::RemoteFetcher::FetchError do
      src.load_specs :latest
    end
  end

  def test_spaceship
    remote    = @source
    specific  = Gem::Source::SpecificFile.new @specs['a-1'].cache_file
    installed = Gem::Source::Installed.new
    local     = Gem::Source::Local.new

    assert_equal( 0, remote.   <=>(remote),    'remote    <=> remote')

    assert_equal(-1, remote.   <=>(specific),  'remote    <=> specific')
    assert_equal( 1, specific. <=>(remote),    'specific  <=> remote')

    assert_equal(-1, remote.   <=>(local),     'remote    <=> local')
    assert_equal( 1, local.    <=>(remote),    'local     <=> remote')

    assert_equal(-1, remote.   <=>(installed), 'remote    <=> installed')
    assert_equal( 1, installed.<=>(remote),    'installed <=> remote')

    no_uri = @source.dup
    no_uri.instance_variable_set :@uri, nil

    assert_equal(-1, remote.   <=>(no_uri),    'remote <=> no_uri')
  end

  def test_update_cache_eh
    assert @source.update_cache?
  end

  def test_update_cache_eh_home_nonexistent
    FileUtils.rmdir Gem.user_home

    refute @source.update_cache?
  end

end

