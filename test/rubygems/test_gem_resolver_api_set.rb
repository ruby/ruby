# frozen_string_literal: true
require_relative 'helper'

class TestGemResolverAPISet < Gem::TestCase
  def setup
    super

    @DR = Gem::Resolver
    @dep_uri = URI "#{@gem_repo}info/"
  end

  def test_initialize
    set = @DR::APISet.new

    assert_equal URI('https://index.rubygems.org/info/'),            set.dep_uri
    assert_equal URI('https://index.rubygems.org/'),                 set.uri
    assert_equal Gem::Source.new(URI('https://index.rubygems.org')), set.source
  end

  def test_initialize_deeper_uri
    set = @DR::APISet.new 'https://rubygemsserver.com/mygems/info'

    assert_equal URI('https://rubygemsserver.com/mygems/info'),       set.dep_uri
    assert_equal URI('https://rubygemsserver.com/'),                  set.uri
    assert_equal Gem::Source.new(URI('https://rubygemsserver.com/')), set.source
  end

  def test_initialize_uri
    set = @DR::APISet.new @dep_uri

    assert_equal URI("#{@gem_repo}info/"), set.dep_uri
    assert_equal URI("#{@gem_repo}"), set.uri
  end

  def test_find_all
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [] },
    ]

    @fetcher.data["#{@dep_uri}a"] = "---\n1  "

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    expected = [
      @DR::APISpecification.new(set, data.first),
    ]

    assert_equal expected, set.find_all(a_dep)
  end

  def test_find_all_prereleases
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [] },
      { :name         => 'a',
        :number       => '2.a',
        :platform     => 'ruby',
        :dependencies => [] },
    ]

    @fetcher.data["#{@dep_uri}a"] = "---\n1\n2.a"

    set = @DR::APISet.new @dep_uri
    set.prerelease = true

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    expected = [
      @DR::APISpecification.new(set, data.first),
      @DR::APISpecification.new(set, data.last),
    ]

    assert_equal expected, set.find_all(a_dep)
  end

  def test_find_all_cache
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [] },
    ]

    @fetcher.data["#{@dep_uri}a"] = "---\n1  "

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    set.prefetch [a_dep]

    expected = [
      @DR::APISpecification.new(set, data.first),
    ]

    assert_equal expected, set.find_all(a_dep)

    @fetcher.data.delete "#{@dep_uri}a"
  end

  def test_find_all_local
    set = @DR::APISet.new @dep_uri
    set.remote = false

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    assert_empty set.find_all(a_dep)
  end

  def test_find_all_missing
    spec_fetcher

    @fetcher.data["#{@dep_uri}a"] = "---"

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    assert_empty set.find_all(a_dep)

    @fetcher.data.delete "#{@dep_uri}a"

    assert_empty set.find_all(a_dep)
  end

  def test_prefetch
    spec_fetcher

    @fetcher.data["#{@dep_uri}a"] = "---\n1  \n"
    @fetcher.data["#{@dep_uri}b"] = "---"

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep, b_dep]

    assert_equal %w[a-1], set.find_all(a_dep).map {|s| s.full_name }
    assert_empty          set.find_all(b_dep)
  end

  def test_prefetch_cache
    spec_fetcher

    @fetcher.data["#{@dep_uri}a"] = "---\n1  \n"

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep]

    @fetcher.data.delete "#{@dep_uri}a"
    @fetcher.data["#{@dep_uri}?b"] = "---"

    set.prefetch [a_dep, b_dep]
  end

  def test_prefetch_cache_missing
    spec_fetcher

    @fetcher.data["#{@dep_uri}a"] = "---\n1  \n"
    @fetcher.data["#{@dep_uri}b"] = "---"

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep, b_dep]

    @fetcher.data.delete "#{@dep_uri}a"
    @fetcher.data.delete "#{@dep_uri}b"

    set.prefetch [a_dep, b_dep]
  end

  def test_prefetch_local
    spec_fetcher

    @fetcher.data["#{@dep_uri}a"] = "---\n1  \n"
    @fetcher.data["#{@dep_uri}b"] = "---"

    set = @DR::APISet.new @dep_uri
    set.remote = false

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep, b_dep]

    assert_empty set.instance_variable_get :@data
  end
end
