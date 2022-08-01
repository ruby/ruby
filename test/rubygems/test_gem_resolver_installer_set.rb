# frozen_string_literal: true
require_relative "helper"

class TestGemResolverInstallerSet < Gem::TestCase
  def test_add_always_install
    spec_fetcher do |fetcher|
      fetcher.download "a", 1
      fetcher.download "a", 2
    end

    util_gem "a", 1

    set = Gem::Resolver::InstallerSet.new :both

    set.add_always_install dep("a")

    assert_equal %w[a-2], set.always_install.map {|s| s.full_name }

    e = assert_raise Gem::UnsatisfiableDependencyError do
      set.add_always_install dep("b")
    end

    assert_equal dep("b"), e.dependency.dependency
  end

  def test_add_always_install_errors
    @stub_fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @stub_fetcher

    set = Gem::Resolver::InstallerSet.new :both

    e = assert_raise Gem::UnsatisfiableDependencyError do
      set.add_always_install dep "a"
    end

    refute_empty e.errors
  end

  def test_add_always_install_platform
    spec_fetcher do |fetcher|
      fetcher.download "a", 1
      fetcher.download "a", 2 do |s|
        s.platform = Gem::Platform.new "x86-freebsd-9"
      end
    end

    set = Gem::Resolver::InstallerSet.new :both

    set.add_always_install dep("a")

    assert_equal %w[a-1], set.always_install.map {|s| s.full_name }
  end

  def test_add_always_install_index_spec_platform
    a_1_local, a_1_local_gem = util_gem "a", 1 do |s|
      s.platform = Gem::Platform.local
    end

    FileUtils.mv a_1_local_gem, @tempdir

    set = Gem::Resolver::InstallerSet.new :both
    set.add_always_install dep("a")

    assert_equal [Gem::Platform.local], set.always_install.map {|s| s.platform }
  end

  def test_add_always_install_prerelease
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1
      fetcher.gem "a", "3.a"
    end

    set = Gem::Resolver::InstallerSet.new :both

    set.add_always_install dep("a")

    assert_equal %w[a-1], set.always_install.map {|s| s.full_name }
  end

  def test_add_always_install_prerelease_github_problem
    spec_fetcher do |fetcher|
      fetcher.gem "a", 1
    end

    # Github has an issue in which it will generate a misleading prerelease output in its RubyGems server API and
    # returns a 0 version for the gem while it doesn't exist.
    @fetcher.data["#{@gem_repo}prerelease_specs.#{Gem.marshal_version}.gz"] = util_gzip(Marshal.dump([
      Gem::NameTuple.new("a", Gem::Version.new(0), "ruby"),
    ]))

    set = Gem::Resolver::InstallerSet.new :both

    set.add_always_install dep("a")

    assert_equal %w[a-1], set.always_install.map {|s| s.full_name }
  end

  def test_add_always_install_prerelease_only
    spec_fetcher do |fetcher|
      fetcher.gem "a", "3.a"
    end

    set = Gem::Resolver::InstallerSet.new :both

    assert_raise Gem::UnsatisfiableDependencyError do
      set.add_always_install dep("a")
    end
  end

  def test_add_local
    a_1, a_1_gem = util_gem "a", 1

    a_1_source = Gem::Source::SpecificFile.new a_1_gem

    set = Gem::Resolver::InstallerSet.new :both

    set.add_local File.basename(a_1_gem), a_1, a_1_source

    assert set.local? File.basename(a_1_gem)

    FileUtils.rm a_1_gem
    util_clear_gems

    req = Gem::Resolver::DependencyRequest.new dep("a"), nil

    assert_equal %w[a-1], set.find_all(req).map {|spec| spec.full_name }
  end

  def test_consider_local_eh
    set = Gem::Resolver::InstallerSet.new :remote

    refute set.consider_local?

    set = Gem::Resolver::InstallerSet.new :both

    assert set.consider_local?

    set = Gem::Resolver::InstallerSet.new :local

    assert set.consider_local?
  end

  def test_consider_remote_eh
    set = Gem::Resolver::InstallerSet.new :remote

    assert set.consider_remote?

    set = Gem::Resolver::InstallerSet.new :both

    assert set.consider_remote?

    set = Gem::Resolver::InstallerSet.new :local

    refute set.consider_remote?
  end

  def test_errors
    set = Gem::Resolver::InstallerSet.new :both

    set.instance_variable_get(:@errors) << :a

    req = Gem::Resolver::DependencyRequest.new dep("a"), nil

    set.find_all req

    assert_equal [:a, set.remote_set.errors.first], set.errors
  end

  def test_find_all_always_install
    spec_fetcher do |fetcher|
      fetcher.download "a", 2
    end

    util_gem "a", 1

    set = Gem::Resolver::InstallerSet.new :both

    set.add_always_install dep "a"

    req = Gem::Resolver::DependencyRequest.new dep("a"), nil

    assert_equal %w[a-2], set.find_all(req).map {|spec| spec.full_name }
  end

  def test_find_all_prerelease
    spec_fetcher do |fetcher|
      fetcher.download "a", "1"
      fetcher.download "a", "1.a"
    end

    set = Gem::Resolver::InstallerSet.new :both

    req = Gem::Resolver::DependencyRequest.new dep("a"), nil

    assert_equal %w[a-1], set.find_all(req).map {|spec| spec.full_name }

    req = Gem::Resolver::DependencyRequest.new dep("a", ">= 0.a"), nil

    assert_equal %w[a-1 a-1.a],
                 set.find_all(req).map {|spec| spec.full_name }.sort
  end

  def test_load_spec
    specs = spec_fetcher do |fetcher|
      fetcher.spec "a", 2
      fetcher.spec "a", 2 do |s|
        s.platform = Gem::Platform.local
      end
    end

    source = Gem::Source.new @gem_repo
    version = v 2

    set = Gem::Resolver::InstallerSet.new :remote

    spec = set.load_spec "a", version, Gem::Platform.local, source

    assert_equal specs["a-2-#{Gem::Platform.local}"].full_name, spec.full_name
  end

  def test_prefetch
    set = Gem::Resolver::InstallerSet.new :remote
    def (set.remote_set).prefetch(_)
      raise "called"
    end
    assert_raise(RuntimeError) { set.prefetch(nil) }

    set = Gem::Resolver::InstallerSet.new :local
    def (set.remote_set).prefetch(_)
      raise "called"
    end
    assert_nil set.prefetch(nil)
  end

  def test_prerelease_equals
    set = Gem::Resolver::InstallerSet.new :remote

    refute set.prerelease
    refute set.remote_set.prerelease

    set.prerelease = true

    assert set.prerelease
    assert set.remote_set.prerelease
  end

  def test_remote_equals_both
    set = Gem::Resolver::InstallerSet.new :both
    set.remote = true

    assert set.consider_local?
    assert set.consider_remote?

    set = Gem::Resolver::InstallerSet.new :both
    set.remote = false

    assert set.consider_local?
    refute set.consider_remote?
  end

  def test_remote_equals_local
    set = Gem::Resolver::InstallerSet.new :local
    set.remote = true

    assert set.consider_local?
    assert set.consider_remote?

    set = Gem::Resolver::InstallerSet.new :local
    set.remote = false

    assert set.consider_local?
    refute set.consider_remote?
  end

  def test_remote_equals_remote
    set = Gem::Resolver::InstallerSet.new :remote
    set.remote = true

    refute set.consider_local?
    assert set.consider_remote?

    set = Gem::Resolver::InstallerSet.new :remote
    set.remote = false

    refute set.consider_local?
    refute set.consider_remote?
  end
end
