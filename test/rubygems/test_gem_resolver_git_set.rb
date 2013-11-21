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

  def test_find_all
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep 'a', '~> 1.0'
    req = Gem::Resolver::ActivationRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    found = @set.find_all dependency

    assert_equal [@set.specs['a']], found
  end

  def test_prefetch
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep name
    req = Gem::Resolver::ActivationRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    refute_empty @set.specs
  end

  def test_prefetch_cache
    name, _, repository, = git_gem

    @set.add_git_gem name, repository, 'master', false

    dependency = dep name
    req = Gem::Resolver::ActivationRequest.new dependency, nil
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
    req = Gem::Resolver::ActivationRequest.new dependency, nil
    @reqs.add req

    @set.prefetch @reqs

    refute_empty @set.specs, 'the git source does not filter'
  end

end

