# frozen_string_literal: true
require_relative "helper"
require "rubygems/source"

class TestGemSourceSubpathProblem < Gem::TestCase
  def tuple(*args)
    Gem::NameTuple.new(*args)
  end

  def setup
    super

    @gem_repo = "http://gems.example.com/private"

    spec_fetcher

    @source = Gem::Source.new(@gem_repo)

    util_make_gems
  end

  def test_dependency_resolver_set
    response = Net::HTTPResponse.new "1.1", 200, "OK"
    response.uri = URI("http://example")

    @fetcher.data["#{@gem_repo}/"] = response

    set = @source.dependency_resolver_set

    assert_kind_of Gem::Resolver::APISet, set
  end

  def test_fetch_spec
    @fetcher.data["#{@gem_repo}/#{Gem::MARSHAL_SPEC_DIR}#{@a1.spec_name}.rz"] = Zlib::Deflate.deflate(Marshal.dump(@a1))

    spec = @source.fetch_spec tuple("a", Gem::Version.new(1), "ruby")
    assert_equal @a1.full_name, spec.full_name
  end

  def test_load_specs
    @fetcher.data["#{@gem_repo}/latest_specs.#{Gem.marshal_version}.gz"] = util_gzip(Marshal.dump([
      Gem::NameTuple.new(@a1.name, @a1.version, "ruby"),
      Gem::NameTuple.new(@b2.name, @b2.version, "ruby"),
    ]))

    released = @source.load_specs(:latest).map {|spec| spec.full_name }
    assert_equal %W[a-1 b-2], released
  end
end
