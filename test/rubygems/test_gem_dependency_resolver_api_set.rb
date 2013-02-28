require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverAPISet < Gem::TestCase

  def setup
    super

    @DR = Gem::DependencyResolver

    @api_set = @DR::APISet.new
    @uri = 'https://rubygems.org/api/v1/dependencies'
    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher
  end

  def test_find_all
    b_entry = {
      :name         => 'b',
      :number       => '2',
      :platform     => 'ruby',
      :dependencies => [['a', '>= 0']],
    }

    @fetcher.data["#{@uri}?gems=b"] = Marshal.dump [b_entry]

    b_req = @DR::DependencyRequest.new dep('b', '>= 0'), nil

    expected = [
      @DR::APISpecification.new(@api_set, b_entry)
    ]

    assert_equal expected, @api_set.find_all(b_req)
  end

  def test_prefetch
    b_entry = {
      :name         => 'b',
      :number       => '2',
      :platform     => 'ruby',
      :dependencies => [['a', '>= 0']],
    }

    a_entry = {
      :name         => 'a',
      :number       => '2',
      :platform     => 'ruby',
      :dependencies => [],
    }

    @fetcher.data["#{@uri}?gems=a,b"] = Marshal.dump [a_entry, b_entry]

    a_req = @DR::DependencyRequest.new dep('a', '>= 0'), nil
    b_req = @DR::DependencyRequest.new dep('b', '>= 0'), nil

    @api_set.prefetch([b_req, a_req])

    assert_equal [a_entry], @api_set.versions('a')
    assert_equal [b_entry], @api_set.versions('b')
  end

  def test_versions_cache
    entry = {
      :name         => 'b',
      :number       => '2',
      :platform     => 'ruby',
      :dependencies => [['a', '>= 0']],
    }

    @fetcher.data["#{@uri}?gems=b"] = Marshal.dump [entry]

    assert_equal [entry], @api_set.versions('b')

    @fetcher.data["#{@uri}?gems=b"] = 'garbage'

    assert_equal [entry], @api_set.versions('b'), 'version data must be cached'
  end

end

