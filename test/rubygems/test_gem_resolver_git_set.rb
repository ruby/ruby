# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverGitSet < Gem::TestCase

  def setup
    super

    @set = Gem::Resolver::GitSet.new

    @reqs = Gem::Resolver::RequirementList.new
  end

  def test_add_git_gem
    name, version, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep 'a'

    specs = @set.find_all dependency

    assert_equal "#{name}-#{version}", specs.first.full_name

    refute @set.need_submodules[repository]
  end

  def test_add_git_gem_submodules
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', true

    dependency = dep 'a'

    refute_empty @set.find_all dependency

    assert @set.need_submodules[repository]
  end

  def test_add_git_spec
    name, version, repository, revision = git_gem

    @set.add_git_spec name, version, repository, revision, true

    dependency = dep 'a'

    specs = @set.find_all dependency

    spec = specs.first

    assert_equal "#{name}-#{version}", spec.full_name

    assert @set.need_submodules[repository]

    refute_path_exists spec.source.repo_cache_dir
  end

  def test_find_all
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep 'a', '~> 1.0'
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    found = @set.find_all dependency

    assert_equal [@set.specs['a']], found
  end

  def test_find_all_local
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false
    @set.remote = false

    dependency = dep 'a', '~> 1.0'
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    assert_empty @set.find_all dependency
  end

  def test_find_all_prerelease
    name, _, repository, = git_gem 'a', '1.a'

    @set.add_git_gem name, repository, 'master', false

    dependency = dep 'a', '>= 0'
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    found = @set.find_all dependency

    assert_empty found

    dependency = dep 'a', '>= 0.a'
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    found = @set.find_all dependency

    refute_empty found
  end

  def test_root_dir
    assert_equal Gem.dir, @set.root_dir

    @set.root_dir = "#{@gemhome}2"

    assert_equal "#{@gemhome}2", @set.root_dir
  end

  def test_prefetch
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep name
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    refute_empty @set.specs
  end

  def test_prefetch_cache
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep name
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    spec = @set.specs[name]

    @set.prefetch @reqs

    assert_same spec, @set.specs[name]
  end

  def test_prefetch_filter
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep 'b'
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    refute_empty @set.specs, 'the git source does not filter'
  end

  def test_prefetch_root_dir
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep name
    req = Gem::Resolver::DependencyRequest.new dependency, nil
    @reqs.add req

    @set.root_dir = "#{@gemhome}2"

    @set.prefetch @reqs

    refute_empty @set.specs

    spec = @set.specs.values.first

    assert_equal "#{@gemhome}2", spec.source.root_dir
  end

end

