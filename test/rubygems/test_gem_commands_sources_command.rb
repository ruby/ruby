# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/sources_command'

class TestGemCommandsSourcesCommand < Gem::TestCase

  def setup
    super

    spec_fetcher

    @cmd = Gem::Commands::SourcesCommand.new

    @new_repo = "http://beta-gems.example.com"
  end

  def test_initialize_proxy
    assert @cmd.handles?(['--http-proxy', 'http://proxy.example.com'])
  end

  def test_execute
    @cmd.handle_options []

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
*** CURRENT SOURCES ***

#{@gem_repo}
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    specs = Gem::Specification.map { |spec|
      [spec.name, spec.version, spec.original_platform]
    }

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap specs_dump_gz do |io|
      Marshal.dump specs, io
    end

    @fetcher.data["#{@new_repo}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

    @cmd.handle_options %W[--add #{@new_repo}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal [@gem_repo, @new_repo], Gem.sources

    expected = <<-EOF
#{@new_repo} added to sources
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add_nonexistent_source
    uri = "http://beta-gems.example.com/specs.#{@marshal_version}.gz"
    @fetcher.data[uri] = proc do
      raise Gem::RemoteFetcher::FetchError.new('it died', uri)
    end

    @cmd.handle_options %w[--add http://beta-gems.example.com]

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = <<-EOF
Error fetching http://beta-gems.example.com:
\tit died (#{uri})
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add_redundant_source
    @cmd.handle_options %W[--add #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EOF
source #{@gem_repo} already present in the cache
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add_http_rubygems_org
    http_rubygems_org = 'http://rubygems.org'

    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    specs = Gem::Specification.map { |spec|
      [spec.name, spec.version, spec.original_platform]
    }

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap specs_dump_gz do |io|
      Marshal.dump specs, io
    end

    @fetcher.data["#{http_rubygems_org}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

    @cmd.handle_options %W[--add #{http_rubygems_org}]

    ui = Gem::MockGemUi.new "n"

    use_ui ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EXPECTED
    EXPECTED

    assert_equal expected, @ui.output
    assert_empty @ui.error
  end

  def test_execute_add_bad_uri
    @cmd.handle_options %w[--add beta-gems.example.com]

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EOF
beta-gems.example.com is not a URI
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_clear_all
    @cmd.handle_options %w[--clear-all]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
*** Removed specs cache ***
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    dir = Gem.spec_cache_dir
    refute File.exist?(dir), 'cache dir removed'
  end

  def test_execute_list
    @cmd.handle_options %w[--list]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
*** CURRENT SOURCES ***

#{@gem_repo}
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remove
    @cmd.handle_options %W[--remove #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remove_no_network
    @cmd.handle_options %W[--remove #{@gem_repo}]

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_update
    @cmd.handle_options %w[--update]

    spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "source cache successfully updated\n", @ui.output
    assert_equal '', @ui.error
  end

end

