# frozen_string_literal: true

require_relative "helper"
require "rubygems/request_set"

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

    rs.gem "a", "1"
    rs.gem "a", "2"

    assert_equal [dep("a", "= 1", "= 2")], rs.dependencies
  end

  def test_import
    rs = Gem::RequestSet.new
    rs.gem "a"

    rs.import [dep("b")]

    assert_equal [dep("a"), dep("b")], rs.dependencies
  end

  def test_install_from_gemdeps
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    done_installing_ran = false

    Gem.done_installing do |_installer, _specs|
      done_installing_ran = true
    end

    rs = Gem::RequestSet.new
    installed = []

    File.open "gem.deps.rb", "w" do |io|
      io.puts 'gem "a"'
      io.flush

      result = rs.install_from_gemdeps :gemdeps => io.path do |req, _installer|
        installed << req.full_name
      end

      assert_kind_of Array, result # what is supposed to be in here?
    end

    assert_includes installed, "a-2"
    assert_path_exist File.join @gemhome, "gems", "a-2"
    assert_path_exist "gem.deps.rb.lock"

    assert rs.remote
    refute done_installing_ran
  end

  def test_install_from_gemdeps_explain
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    rs = Gem::RequestSet.new

    File.open "gem.deps.rb", "w" do |io|
      io.puts 'gem "a"'
      io.flush

      expected = <<-EXPECTED
Gems to install:
  a-2
      EXPECTED

      actual, _ = capture_output do
        rs.install_from_gemdeps :gemdeps => io.path, :explain => true
      end
      assert_equal(expected, actual)
    end
  end

  def test_install_from_gemdeps_install_dir
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    util_clear_gems
    assert_path_not_exist File.join Gem.dir, "gems", "a-2"

    rs = Gem::RequestSet.new
    installed = []

    File.open "gem.deps.rb", "w" do |io|
      io.puts 'gem "a"'
    end

    options = {
      :gemdeps => "gem.deps.rb",
      :install_dir => "#{@gemhome}2",
    }

    rs.install_from_gemdeps options do |req, _installer|
      installed << req.full_name
    end

    assert_includes installed, "a-2"
    assert_path_not_exist File.join Gem.dir, "gems", "a-2"
  end

  def test_install_from_gemdeps_local
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    rs = Gem::RequestSet.new

    File.open "gem.deps.rb", "w" do |io|
      io.puts 'gem "a"'
      io.flush

      assert_raise Gem::UnsatisfiableDependencyError do
        rs.install_from_gemdeps :gemdeps => io.path, :domain => :local
      end
    end

    refute rs.remote
  end

  def test_install_from_gemdeps_lockfile
    spec_fetcher do |fetcher|
      fetcher.download "a", 1
      fetcher.download "a", 2
      fetcher.download "b", 1, "a" => ">= 0"
    end

    rs = Gem::RequestSet.new
    installed = []

    File.open "gem.deps.rb.lock", "w" do |io|
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

    File.open "gem.deps.rb", "w" do |io|
      io.puts 'gem "b"'
    end

    rs.install_from_gemdeps :gemdeps => "gem.deps.rb" do |req, _installer|
      installed << req.full_name
    end

    assert_includes installed, "b-1"
    assert_includes installed, "a-1"

    assert_path_exist File.join @gemhome, "specifications", "a-1.gemspec"
    assert_path_exist File.join @gemhome, "specifications", "b-1.gemspec"
  end

  def test_install_from_gemdeps_complex_dependencies
    quick_gem("z", 1)
    quick_gem("z", "1.0.1")
    quick_gem("z", "1.0.2")
    quick_gem("z", "1.0.3")
    quick_gem("z", 2)

    spec_fetcher do |fetcher|
      fetcher.download "z", 1
    end

    rs = Gem::RequestSet.new
    installed = []

    File.open "Gemfile.lock", "w" do |io|
      io.puts <<-LOCKFILE
GEM
  remote: #{@gem_repo}
  specs:
    z (1)

PLATFORMS
  #{Gem::Platform::RUBY}

DEPENDENCIES
  z (~> 1.0, >= 1.0.1)
      LOCKFILE
    end

    File.open "testo.gemspec", "w" do |io|
      io.puts <<-LOCKFILE
Gem::Specification.new do |spec|
  spec.name = 'testo'
  spec.version = '1.0.0'
  spec.add_dependency('z', '~> 1.0', '>= 1.0.1')
end
      LOCKFILE
    end

    File.open "Gemfile", "w" do |io|
      io.puts("gemspec")
    end

    rs.install_from_gemdeps :gemdeps => "Gemfile" do |req, _installer|
      installed << req.full_name
    end

    assert_includes installed, "z-1.0.3"

    assert_path_exist File.join @gemhome, "specifications", "z-1.0.3.gemspec"
  end

  def test_install_from_gemdeps_version_mismatch
    spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    rs = Gem::RequestSet.new
    installed = []

    File.open "gem.deps.rb", "w" do |io|
      io.puts <<-GEM_DEPS
gem "a"
ruby "0"
      GEM_DEPS

      io.flush

      rs.install_from_gemdeps :gemdeps => io.path do |req, _installer|
        installed << req.full_name
      end
    end

    assert_includes installed, "a-2"
  end

  def test_load_gemdeps
    rs = Gem::RequestSet.new

    tf = Tempfile.open "gem.deps.rb" do |io|
      io.puts 'gem "a"'
      io.flush

      gem_deps = rs.load_gemdeps io.path

      assert_kind_of Gem::RequestSet::GemDependencyAPI, gem_deps
      io
    end
    tf.close!

    assert_equal [dep("a")], rs.dependencies

    assert rs.git_set
    assert rs.vendor_set
  end

  def test_load_gemdeps_installing
    rs = Gem::RequestSet.new

    tf = Tempfile.open "gem.deps.rb" do |io|
      io.puts 'ruby "0"'
      io.puts 'gem "a"'
      io.flush

      gem_deps = rs.load_gemdeps io.path, [], true

      assert_kind_of Gem::RequestSet::GemDependencyAPI, gem_deps
      io
    end
    tf.close!

    assert_equal [dep("a")], rs.dependencies
  end

  def test_load_gemdeps_without_groups
    rs = Gem::RequestSet.new

    tf = Tempfile.open "gem.deps.rb" do |io|
      io.puts 'gem "a", :group => :test'
      io.flush

      rs.load_gemdeps io.path, [:test]
      io
    end
    tf.close!

    assert_empty rs.dependencies
  end

  def test_resolve
    a = util_spec "a", "2", "b" => ">= 2"
    b = util_spec "b", "2"

    rs = Gem::RequestSet.new
    rs.gem "a"

    orig_errors = rs.errors

    res = rs.resolve StaticSet.new([a, b])
    assert_equal 2, res.size

    names = res.map(&:full_name).sort

    assert_equal ["a-2", "b-2"], names

    refute_same orig_errors, rs.errors
  end

  def test_bug_bug_990
    a = util_spec "a", "1.b",  "b" => "~> 1.a"
    b = util_spec "b", "1.b",  "c" => ">= 1"
    c = util_spec "c", "1.1.b"

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.prerelease = true

    res = rs.resolve StaticSet.new([a, b, c])
    assert_equal 3, res.size

    names = res.map(&:full_name).sort

    assert_equal %w[a-1.b b-1.b c-1.1.b], names
  end

  def test_resolve_development
    a = util_spec "a", 1
    spec = Gem::Resolver::SpecSpecification.new nil, a

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.development = true

    res = rs.resolve StaticSet.new [spec]
    assert_equal 1, res.size

    assert rs.resolver.development
    refute rs.resolver.development_shallow
  end

  def test_resolve_development_shallow
    a = util_spec "a", 1 do |s|
      s.add_development_dependency "b"
    end

    b = util_spec "b", 1 do |s|
      s.add_development_dependency "c"
    end

    c = util_spec "c", 1

    a_spec = Gem::Resolver::SpecSpecification.new nil, a
    b_spec = Gem::Resolver::SpecSpecification.new nil, b
    c_spec = Gem::Resolver::SpecSpecification.new nil, c

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.development = true
    rs.development_shallow = true

    res = rs.resolve StaticSet.new [a_spec, b_spec, c_spec]
    assert_equal 2, res.size

    assert rs.resolver.development
    assert rs.resolver.development_shallow
  end

  def test_resolve_git
    name, _, repository, = git_gem

    rs = Gem::RequestSet.new

    tf = Tempfile.open "gem.deps.rb" do |io|
      io.puts <<-GEMS_DEPS_RB
        gem "#{name}", :git => "#{repository}"
      GEMS_DEPS_RB

      io.flush

      rs.load_gemdeps io.path
      io
    end
    tf.close!

    res = rs.resolve
    assert_equal 1, res.size

    names = res.map(&:full_name).sort

    assert_equal %w[a-1], names

    assert_equal [@DR::BestSet, @DR::GitSet, @DR::VendorSet, @DR::SourceSet],
                 rs.sets.map(&:class)
  end

  def test_resolve_ignore_dependencies
    a = util_spec "a", "2", "b" => ">= 2"
    b = util_spec "b", "2"

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.ignore_dependencies = true

    res = rs.resolve StaticSet.new([a, b])
    assert_equal 1, res.size

    names = res.map(&:full_name).sort

    assert_equal %w[a-2], names
  end

  def test_resolve_incompatible
    a1 = util_spec "a", 1
    a2 = util_spec "a", 2

    rs = Gem::RequestSet.new
    rs.gem "a", "= 1"
    rs.gem "a", "= 2"

    set = StaticSet.new [a1, a2]

    assert_raise Gem::UnsatisfiableDependencyError do
      rs.resolve set
    end
  end

  def test_resolve_vendor
    a_name, _, a_directory = vendor_gem "a", 1 do |s|
      s.add_dependency "b", "~> 2.0"
    end

    b_name, _, b_directory = vendor_gem "b", 2

    rs = Gem::RequestSet.new

    tf = Tempfile.open "gem.deps.rb" do |io|
      io.puts <<-GEMS_DEPS_RB
        gem "#{a_name}", :path => "#{a_directory}"
        gem "#{b_name}", :path => "#{b_directory}"
      GEMS_DEPS_RB

      io.flush

      rs.load_gemdeps io.path
      io
    end
    tf.close!

    res = rs.resolve
    assert_equal 2, res.size

    names = res.map(&:full_name).sort

    assert_equal ["a-1", "b-2"], names

    assert_equal [@DR::BestSet, @DR::GitSet, @DR::VendorSet, @DR::SourceSet],
                 rs.sets.map(&:class)
  end

  def test_sorted_requests
    a = util_spec "a", "2", "b" => ">= 2"
    b = util_spec "b", "2", "c" => ">= 2"
    c = util_spec "c", "2"

    rs = Gem::RequestSet.new
    rs.gem "a"

    rs.resolve StaticSet.new([a, b, c])

    names = rs.sorted_requests.map(&:full_name)
    assert_equal %w[c-2 b-2 a-2], names
  end

  def test_install
    done_installing_ran = false

    Gem.done_installing do
      done_installing_ran = true
    end

    spec_fetcher do |fetcher|
      fetcher.download "a", "1", "b" => "= 1"
      fetcher.download "b", "1"
    end

    rs = Gem::RequestSet.new
    rs.gem "a"

    rs.resolve

    reqs       = []
    installers = []

    installed = rs.install({}) do |req, installer|
      reqs       << req
      installers << installer
    end

    assert_equal %w[b-1 a-1], reqs.map(&:full_name)
    assert_equal %w[b-1 a-1],
                 installers.map {|installer| installer.spec.full_name }

    assert_path_exist File.join @gemhome, "specifications", "a-1.gemspec"
    assert_path_exist File.join @gemhome, "specifications", "b-1.gemspec"

    assert_equal %w[b-1 a-1], installed.map(&:full_name)

    assert done_installing_ran
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
      assert_equal @tempdir, ENV["GEM_HOME"]
    end

    assert_path_exist File.join @tempdir, "specifications", "a-1.gemspec"
    assert_path_exist File.join @tempdir, "specifications", "b-1.gemspec"

    assert_equal %w[b-1 a-1], installed.map(&:full_name)
  end

  def test_install_into_development_shallow
    spec_fetcher do |fetcher|
      fetcher.gem "a", "1" do |s|
        s.add_development_dependency "b", "= 1"
      end

      fetcher.gem "b", "1" do |s|
        s.add_development_dependency "c", "= 1"
      end

      fetcher.spec "c", "1"
    end

    rs = Gem::RequestSet.new
    rs.development         = true
    rs.development_shallow = true
    rs.gem "a"

    rs.resolve

    options = {
      :development => true,
      :development_shallow => true,
    }

    installed = rs.install_into @tempdir, true, options do
      assert_equal @tempdir, ENV["GEM_HOME"]
    end

    assert_equal %w[a-1 b-1], installed.map(&:full_name).sort
  end

  def test_sorted_requests_development_shallow
    a = util_spec "a", 1 do |s|
      s.add_development_dependency "b"
    end

    b = util_spec "b", 1 do |s|
      s.add_development_dependency "c"
    end

    c = util_spec "c", 1

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.development = true
    rs.development_shallow = true

    a_spec = Gem::Resolver::SpecSpecification.new nil, a
    b_spec = Gem::Resolver::SpecSpecification.new nil, b
    c_spec = Gem::Resolver::SpecSpecification.new nil, c

    rs.resolve StaticSet.new [a_spec, b_spec, c_spec]

    assert_equal %w[b-1 a-1], rs.sorted_requests.map(&:full_name)
  end

  def test_tsort_each_child_development
    a = util_spec "a", 1 do |s|
      s.add_development_dependency "b"
    end

    b = util_spec "b", 1 do |s|
      s.add_development_dependency "c"
    end

    c = util_spec "c", 1

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.development = true
    rs.development_shallow = true

    a_spec = Gem::Resolver::SpecSpecification.new nil, a
    b_spec = Gem::Resolver::SpecSpecification.new nil, b
    c_spec = Gem::Resolver::SpecSpecification.new nil, c

    rs.resolve StaticSet.new [a_spec, b_spec, c_spec]

    a_req = Gem::Resolver::ActivationRequest.new a_spec, nil

    deps = rs.enum_for(:tsort_each_child, a_req).to_a

    assert_equal %w[b], deps.map(&:name)
  end

  def test_tsort_each_child_development_shallow
    a = util_spec "a", 1 do |s|
      s.add_development_dependency "b"
    end

    b = util_spec "b", 1 do |s|
      s.add_development_dependency "c"
    end

    c = util_spec "c", 1

    rs = Gem::RequestSet.new
    rs.gem "a"
    rs.development = true
    rs.development_shallow = true

    a_spec = Gem::Resolver::SpecSpecification.new nil, a
    b_spec = Gem::Resolver::SpecSpecification.new nil, b
    c_spec = Gem::Resolver::SpecSpecification.new nil, c

    rs.resolve StaticSet.new [a_spec, b_spec, c_spec]

    b_req = Gem::Resolver::ActivationRequest.new b_spec, nil

    deps = rs.enum_for(:tsort_each_child, b_req).to_a

    assert_empty deps
  end
end
