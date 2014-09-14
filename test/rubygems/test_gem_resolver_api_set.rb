require 'rubygems/test_case'

class TestGemResolverAPISet < Gem::TestCase

  def setup
    super

    @DR = Gem::Resolver
    @dep_uri = URI "#{@gem_repo}api/v1/dependencies"
  end

  def test_initialize
    set = @DR::APISet.new

    assert_equal URI('https://rubygems.org/api/v1/dependencies'), set.dep_uri
    assert_equal URI('https://rubygems.org'),                     set.uri
    assert_equal Gem::Source.new(URI('https://rubygems.org')),    set.source
  end

  def test_initialize_deeper_uri
    set = @DR::APISet.new 'https://rubygemsserver.com/mygems/api/v1/dependencies'

    assert_equal URI('https://rubygemsserver.com/mygems/api/v1/dependencies'), set.dep_uri
    assert_equal URI('https://rubygemsserver.com/mygems/'),                    set.uri
    assert_equal Gem::Source.new(URI('https://rubygemsserver.com/mygems/')),    set.source
  end

  def test_initialize_uri
    set = @DR::APISet.new @dep_uri

    assert_equal URI("#{@gem_repo}api/v1/dependencies"), set.dep_uri
    assert_equal URI("#{@gem_repo}"),                     set.uri
  end

  def test_find_all
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [], },
    ]

    @fetcher.data["#{@dep_uri}?gems=a"] = Marshal.dump data

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    expected = [
      @DR::APISpecification.new(set, data.first)
    ]

    assert_equal expected, set.find_all(a_dep)
  end

  def test_find_all_cache
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [], },
    ]

    @fetcher.data["#{@dep_uri}?gems=a"] = Marshal.dump data

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    set.prefetch [a_dep]

    expected = [
      @DR::APISpecification.new(set, data.first)
    ]

    assert_equal expected, set.find_all(a_dep)

    @fetcher.data.delete "#{@dep_uri}?gems=a"
  end

  def test_find_all_local
    set = @DR::APISet.new @dep_uri
    set.remote = false

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    assert_empty set.find_all(a_dep)
  end

  def test_find_all_missing
    spec_fetcher

    @fetcher.data["#{@dep_uri}?gems=a"] = Marshal.dump []

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil

    assert_empty set.find_all(a_dep)

    @fetcher.data.delete "#{@dep_uri}?gems=a"

    assert_empty set.find_all(a_dep)
  end

  def test_prefetch
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [], },
    ]

    @fetcher.data["#{@dep_uri}?gems=a,b"] = Marshal.dump data
    @fetcher.data["#{@dep_uri}?gems=b"]   = Marshal.dump []

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep, b_dep]

    assert_equal %w[a-1], set.find_all(a_dep).map { |s| s.full_name }
    assert_empty          set.find_all(b_dep)
  end

  def test_prefetch_cache
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [], },
    ]

    @fetcher.data["#{@dep_uri}?gems=a"] = Marshal.dump data

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep]

    @fetcher.data.delete "#{@dep_uri}?gems=a"
    @fetcher.data["#{@dep_uri}?gems=b"]   = Marshal.dump []

    set.prefetch [a_dep, b_dep]
  end

  def test_prefetch_cache_missing
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [], },
    ]

    @fetcher.data["#{@dep_uri}?gems=a,b"] = Marshal.dump data

    set = @DR::APISet.new @dep_uri

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep, b_dep]

    @fetcher.data.delete "#{@dep_uri}?gems=a,b"

    set.prefetch [a_dep, b_dep]
  end

  def test_prefetch_local
    spec_fetcher

    data = [
      { :name         => 'a',
        :number       => '1',
        :platform     => 'ruby',
        :dependencies => [], },
    ]

    @fetcher.data["#{@dep_uri}?gems=a,b"] = Marshal.dump data
    @fetcher.data["#{@dep_uri}?gems=b"]   = Marshal.dump []

    set = @DR::APISet.new @dep_uri
    set.remote = false

    a_dep = @DR::DependencyRequest.new dep('a'), nil
    b_dep = @DR::DependencyRequest.new dep('b'), nil

    set.prefetch [a_dep, b_dep]

    assert_empty set.instance_variable_get :@data
  end

end

