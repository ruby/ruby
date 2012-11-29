require 'rubygems/test_case'
require 'rubygems/request_set'

class TestGemRequestSet < Gem::TestCase
  def setup
    super

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new
  end

  def test_gem
    util_spec "a", "2"

    rs = Gem::RequestSet.new
    rs.gem "a", "= 2"

    assert_equal [Gem::Dependency.new("a", "=2")], rs.dependencies
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

  def test_install_into
    a, ad = util_gem "a", "1", "b" => "= 1"
    b, bd = util_gem "b", "1"

    util_setup_spec_fetcher a, b

    @fetcher.data["http://gems.example.com/gems/#{a.file_name}"] = Gem.read_binary(ad)
    @fetcher.data["http://gems.example.com/gems/#{b.file_name}"] = Gem.read_binary(bd)

    rs = Gem::RequestSet.new
    rs.gem "a"

    rs.resolve

    installed = rs.install_into @tempdir

    assert File.exists?(File.join(@tempdir, "specifications", "a-1.gemspec"))
    assert File.exists?(File.join(@tempdir, "specifications", "b-1.gemspec"))

    assert_equal %w!b-1 a-1!, installed.map { |s| s.full_name }
  end
end
