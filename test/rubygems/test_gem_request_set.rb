require 'rubygems/test_case'
require 'rubygems/request_set'

class TestGemRequestSet < Gem::TestCase
  def setup
    super

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    @DR = Gem::Resolver
  end

  def test_gem
    util_spec "a", "2"

    rs = Gem::RequestSet.new
    rs.gem "a", "= 2"

    assert_equal [Gem::Dependency.new("a", "=2")], rs.dependencies
  end

  def test_gem_duplicate
    rs = Gem::RequestSet.new

    rs.gem 'a', '1'
    rs.gem 'a', '2'

    assert_equal [dep('a', '= 1', '= 2')], rs.dependencies
  end

  def test_import
    rs = Gem::RequestSet.new
    rs.gem 'a'

    rs.import [dep('b')]

    assert_equal [dep('a'), dep('b')], rs.dependencies
  end

  def test_install_from_gemdeps
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    rs = Gem::RequestSet.new
    installed = []

    open 'gem.deps.rb', 'w' do |io|
      io.puts 'gem "a"'
      io.flush

      result = rs.install_from_gemdeps :gemdeps => io.path do |req, installer|
        installed << req.full_name
      end

      assert_kind_of Array, result # what is supposed to be in here?
    end

    assert_includes installed, 'a-2'
    assert_path_exists File.join @gemhome, 'gems', 'a-2'
    assert_path_exists 'gem.deps.rb.lock'
  end

  def test_install_from_gemdeps_install_dir
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    util_clear_gems
    refute_path_exists File.join Gem.dir, 'gems', 'a-2'

    rs = Gem::RequestSet.new
    installed = []

    open 'gem.deps.rb', 'w' do |io|
      io.puts 'gem "a"'
    end

    options = {
      :gemdeps     => 'gem.deps.rb',
      :install_dir => "#{@gemhome}2",
    }

    rs.install_from_gemdeps options do |req, installer|
      installed << req.full_name
    end

    assert_includes installed, 'a-2'
    refute_path_exists File.join Gem.dir, 'gems', 'a-2'
  end

  def test_install_from_gemdeps_lockfile
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
      fetcher.gem 'b', 1, 'a' => '>= 0'
      fetcher.clear
    end

    rs = Gem::RequestSet.new
    installed = []

    open 'gem.deps.rb.lock', 'w' do |io|
      io.puts <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    a (1)
    b (1)
      a (~> 1.0)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  b
      LOCKFILE
    end

    open 'gem.deps.rb', 'w' do |io|
      io.puts 'gem "b"'
    end

    rs.install_from_gemdeps :gemdeps => 'gem.deps.rb' do |req, installer|
      installed << req.full_name
    end

    assert_includes installed, 'b-1'
    assert_includes installed, 'a-1'

    assert_path_exists File.join @gemhome, 'specifications', 'a-1.gemspec'
    assert_path_exists File.join @gemhome, 'specifications', 'b-1.gemspec'
  end

  def test_load_gemdeps
    rs = Gem::RequestSet.new

    Tempfile.open 'gem.deps.rb' do |io|
      io.puts 'gem "a"'
      io.flush

      rs.load_gemdeps io.path
    end

    assert_equal [dep('a')], rs.dependencies

    assert rs.git_set
    assert rs.vendor_set
  end

  def test_load_gemdeps_without_groups
    rs = Gem::RequestSet.new

    Tempfile.open 'gem.deps.rb' do |io|
      io.puts 'gem "a", :group => :test'
      io.flush

      rs.load_gemdeps io.path, [:test]
    end

    assert_empty rs.dependencies
  end

  def test_resolve
    a = util_spec "a", "2", "b" => ">= 2"
    b = util_spec "b", "2"

    rs = Gem::RequestSet.new
    rs.gem "a"

    res = rs.resolve StaticSet.new([a, b])
    assert_equal 2, res.size

    names = res.map { |s| s.full_name }.sort

    assert_equal ["a-2", "b-2"], names
  end

  def test_resolve_git
    name, _, repository, = git_gem

    rs = Gem::RequestSet.new

    Tempfile.open 'gem.deps.rb' do |io|
      io.puts <<-gems_deps_rb
        gem "#{name}", :git => "#{repository}"
      gems_deps_rb

      io.flush

      rs.load_gemdeps io.path
    end

    res = rs.resolve
    assert_equal 1, res.size

    names = res.map { |s| s.full_name }.sort

    assert_equal %w[a-1], names

    assert_equal [@DR::BestSet, @DR::GitSet, @DR::VendorSet],
                 rs.sets.map { |set| set.class }
  end

  def test_resolve_ignore_dependencies
    a = util_spec "a", "2", "b" => ">= 2"
    b = util_spec "b", "2"

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.ignore_dependencies = true

    res = rs.resolve StaticSet.new([a, b])
    assert_equal 1, res.size

    names = res.map { |s| s.full_name }.sort

    assert_equal %w[a-2], names
  end

  def test_resolve_incompatible
    a1 = util_spec 'a', 1
    a2 = util_spec 'a', 2

    rs = Gem::RequestSet.new
    rs.gem 'a', '= 1'
    rs.gem 'a', '= 2'

    set = StaticSet.new [a1, a2]

    assert_raises Gem::UnsatisfiableDependencyError do
      rs.resolve set
    end
  end

  def test_resolve_vendor
    a_name, _, a_directory = vendor_gem 'a', 1 do |s|
      s.add_dependency 'b', '~> 2.0'
    end

    b_name, _, b_directory = vendor_gem 'b', 2

    rs = Gem::RequestSet.new

    Tempfile.open 'gem.deps.rb' do |io|
      io.puts <<-gems_deps_rb
        gem "#{a_name}", :path => "#{a_directory}"
        gem "#{b_name}", :path => "#{b_directory}"
      gems_deps_rb

      io.flush

      rs.load_gemdeps io.path
    end

    res = rs.resolve
    assert_equal 2, res.size

    names = res.map { |s| s.full_name }.sort

    assert_equal ["a-1", "b-2"], names

    assert_equal [@DR::BestSet, @DR::GitSet, @DR::VendorSet],
                 rs.sets.map { |set| set.class }
  end

  def test_sorted_requests
    a = util_spec "a", "2", "b" => ">= 2"
    b = util_spec "b", "2", "c" => ">= 2"
    c = util_spec "c", "2"

    rs = Gem::RequestSet.new
    rs.gem "a"

    rs.resolve StaticSet.new([a, b, c])

    names = rs.sorted_requests.map { |s| s.full_name }
    assert_equal %w!c-2 b-2 a-2!, names
  end

  def test_install
    spec_fetcher do |fetcher|
      fetcher.gem "a", "1", "b" => "= 1"
      fetcher.gem "b", "1"

      fetcher.clear
    end

    rs = Gem::RequestSet.new
    rs.gem 'a'

    rs.resolve

    reqs       = []
    installers = []

    installed = rs.install({}) do |req, installer|
      reqs       << req
      installers << installer
    end

    assert_equal %w[b-1 a-1], reqs.map { |req| req.full_name }
    assert_equal %w[b-1 a-1],
                 installers.map { |installer| installer.spec.full_name }

    assert_path_exists File.join @gemhome, 'specifications', 'a-1.gemspec'
    assert_path_exists File.join @gemhome, 'specifications', 'b-1.gemspec'

    assert_equal %w[b-1 a-1], installed.map { |s| s.full_name }
  end

  def test_install_into
    spec_fetcher do |fetcher|
      fetcher.gem "a", "1", "b" => "= 1"
      fetcher.gem "b", "1"
    end

    rs = Gem::RequestSet.new
    rs.gem "a"

    rs.resolve

    installed = rs.install_into @tempdir do
      assert_equal @tempdir, ENV['GEM_HOME']
    end

    assert_path_exists File.join @tempdir, 'specifications', 'a-1.gemspec'
    assert_path_exists File.join @tempdir, 'specifications', 'b-1.gemspec'

    assert_equal %w!b-1 a-1!, installed.map { |s| s.full_name }
  end
end
