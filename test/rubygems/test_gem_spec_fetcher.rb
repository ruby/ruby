require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/spec_fetcher'

class TestGemSpecFetcher < RubyGemTestCase

  def setup
    super

    @uri = URI.parse @gem_repo

    util_setup_fake_fetcher

    @source_index.add_spec @pl1

    @specs = @source_index.gems.sort.map do |name, spec|
      [spec.name, spec.version, spec.original_platform]
    end.sort

    @fetcher.data["#{@gem_repo}specs.#{Gem.marshal_version}.gz"] =
      util_gzip(Marshal.dump(@specs))

    @latest_specs = @source_index.latest_specs.sort.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] =
      util_gzip(Marshal.dump(@latest_specs))

    @sf = Gem::SpecFetcher.new
  end

  def test_fetch_all
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a1.full_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@a1))
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a2.full_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@a2))

    dep = Gem::Dependency.new 'a', 1
    specs_and_sources = @sf.fetch dep, true

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    expected = [[@a1.full_name, @gem_repo], [@a2.full_name, @gem_repo]]

    assert_equal expected, spec_names

    assert_same specs_and_sources.first.last, specs_and_sources.last.last
  end

  def test_fetch_latest
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a1.full_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@a1))
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a2.full_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@a2))

    dep = Gem::Dependency.new 'a', 1
    specs_and_sources = @sf.fetch dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [[@a2.full_name, @gem_repo]], spec_names
  end

  def test_fetch_legacy_repo
    @fetcher.data.delete "#{@gem_repo}specs.#{Gem.marshal_version}.gz"
    @fetcher.data["#{@gem_repo}yaml"] = ''
    util_setup_source_info_cache @a1, @a2

    dep = Gem::Dependency.new 'a', 1
    specs = nil

    use_ui @ui do
      specs = @sf.fetch dep, true
    end

    expected = <<-EOF
WARNING:  RubyGems 1.2+ index not found for:
\thttp://gems.example.com/

RubyGems will revert to legacy indexes degrading performance.
    EOF

    assert_equal expected, @ui.error

    specs = specs.map { |spec, source_uri| [spec.full_name, source_uri] }

    expected = [
      [@a1.full_name, @gem_repo],
      [@a2.full_name, @gem_repo],
    ]

    assert_equal expected, specs
  end

  def test_fetch_platform
    util_set_arch 'i386-linux'

    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@pl1.original_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@pl1))

    dep = Gem::Dependency.new 'pl', 1
    specs_and_sources = @sf.fetch dep

    spec_names = specs_and_sources.map do |spec, source_uri|
      [spec.full_name, source_uri]
    end

    assert_equal [[@pl1.full_name, @gem_repo]], spec_names
  end

  def test_fetch_spec
    spec_uri = "#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a1.full_name}.gemspec"
    @fetcher.data["#{spec_uri}.rz"] = util_zip(Marshal.dump(@a1))

    spec = @sf.fetch_spec ['a', Gem::Version.new(1), 'ruby'], @uri
    assert_equal @a1.full_name, spec.full_name

    cache_dir = @sf.cache_dir URI.parse(spec_uri)

    cache_file = File.join cache_dir, "#{@a1.full_name}.gemspec"

    assert File.exist?(cache_file)
  end

  def test_fetch_spec_cached
    spec_uri = "#{@gem_repo}/#{Gem::MARSHAL_SPEC_DIR}#{@a1.full_name}.gemspec"
    @fetcher.data["#{spec_uri}.rz"] = nil

    cache_dir = @sf.cache_dir URI.parse(spec_uri)
    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, "#{@a1.full_name}.gemspec"

    open cache_file, 'wb' do |io|
      Marshal.dump @a1, io
    end

    spec = @sf.fetch_spec ['a', Gem::Version.new(1), 'ruby'], @uri
    assert_equal @a1.full_name, spec.full_name
  end

  def test_fetch_spec_platform
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@pl1.original_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@pl1))

    spec = @sf.fetch_spec ['pl', Gem::Version.new(1), 'i386-linux'], @uri

    assert_equal @pl1.full_name, spec.full_name
  end

  def test_fetch_spec_platform_ruby
    @fetcher.data["#{@gem_repo}#{Gem::MARSHAL_SPEC_DIR}#{@a1.full_name}.gemspec.rz"] =
      util_zip(Marshal.dump(@a1))

    spec = @sf.fetch_spec ['a', Gem::Version.new(1), nil], @uri
    assert_equal @a1.full_name, spec.full_name

    spec = @sf.fetch_spec ['a', Gem::Version.new(1), ''], @uri
    assert_equal @a1.full_name, spec.full_name
  end

  def test_find_matching_all
    dep = Gem::Dependency.new 'a', 1
    specs = @sf.find_matching dep, true

    expected = [
      [['a', Gem::Version.new(1), Gem::Platform::RUBY], @gem_repo],
      [['a', Gem::Version.new(2), Gem::Platform::RUBY], @gem_repo],
    ]

    assert_equal expected, specs
  end

  def test_find_matching_latest
    dep = Gem::Dependency.new 'a', 1
    specs = @sf.find_matching dep

    expected = [
      [['a', Gem::Version.new(2), Gem::Platform::RUBY], @gem_repo],
    ]

    assert_equal expected, specs
  end

  def test_find_matching_platform
    util_set_arch 'i386-linux'

    dep = Gem::Dependency.new 'pl', 1
    specs = @sf.find_matching dep

    expected = [
      [['pl', Gem::Version.new(1), 'i386-linux'], @gem_repo],
    ]

    assert_equal expected, specs

    util_set_arch 'i386-freebsd6'

    dep = Gem::Dependency.new 'pl', 1
    specs = @sf.find_matching dep

    assert_equal [], specs
  end

  def test_find_all_platforms
    util_set_arch 'i386-freebsd6'

    dep = Gem::Dependency.new 'pl', 1
    specs = @sf.find_matching dep, false, false

    expected = [
      [['pl', Gem::Version.new(1), 'i386-linux'], @gem_repo],
    ]

    assert_equal expected, specs
  end

  def test_list
    specs = @sf.list

    assert_equal [@uri], specs.keys
    assert_equal @latest_specs, specs[@uri].sort
  end

  def test_list_all
    specs = @sf.list true

    assert_equal [@uri], specs.keys

    assert_equal @specs, specs[@uri].sort
  end

  def test_list_cache
    specs = @sf.list

    assert !specs[@uri].empty?

    @fetcher.data["#{@gem_repo}/latest_specs.#{Gem.marshal_version}.gz"] = nil

    cached_specs = @sf.list

    assert_equal specs, cached_specs
  end

  def test_list_cache_all
    specs = @sf.list true

    assert !specs[@uri].empty?

    @fetcher.data["#{@gem_repo}/specs.#{Gem.marshal_version}.gz"] = nil

    cached_specs = @sf.list true

    assert_equal specs, cached_specs
  end

  def test_list_latest_all
    specs = @sf.list false

    assert_equal [@latest_specs], specs.values

    specs = @sf.list true

    assert_equal [@specs], specs.values, 'specs file not loaded'
  end

  def test_load_specs
    specs = @sf.load_specs @uri, 'specs'

    expected = [
      ['a',      Gem::Version.new(1),     Gem::Platform::RUBY],
      ['a',      Gem::Version.new(2),     Gem::Platform::RUBY],
      ['a_evil', Gem::Version.new(9),     Gem::Platform::RUBY],
      ['c',      Gem::Version.new('1.2'), Gem::Platform::RUBY],
      ['pl',     Gem::Version.new(1),     'i386-linux'],
    ]

    assert_equal expected, specs

    cache_dir = File.join Gem.user_home, '.gem', 'specs', 'gems.example.com%80'
    assert File.exist?(cache_dir), "#{cache_dir} does not exist"

    cache_file = File.join cache_dir, "specs.#{Gem.marshal_version}"
    assert File.exist?(cache_file)
  end

  def test_load_specs_cached
    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] = nil
    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}"] =
      ' ' * Marshal.dump(@latest_specs).length

    cache_dir = File.join Gem.user_home, '.gem', 'specs', 'gems.example.com%80'

    FileUtils.mkdir_p cache_dir

    cache_file = File.join cache_dir, "latest_specs.#{Gem.marshal_version}"

    open cache_file, 'wb' do |io|
      Marshal.dump @latest_specs, io
    end

    latest_specs = @sf.load_specs @uri, 'latest_specs'

    assert_equal @latest_specs, latest_specs
  end

end

