######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/commands/sources_command'

class TestGemCommandsSourcesCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::SourcesCommand.new

    @new_repo = "http://beta-gems.example.com"
  end

  def test_initialize_proxy
    assert @cmd.handles?(['--http-proxy', 'http://proxy.example.com'])
  end

  def test_execute
    util_setup_spec_fetcher
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
    util_setup_fake_fetcher

    si = Gem::SourceIndex.new
    si.add_spec @a1

    specs = si.map do |_, spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap specs_dump_gz do |io|
      Marshal.dump specs, io
    end

    @fetcher.data["#{@new_repo}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

    @cmd.handle_options %W[--add #{@new_repo}]

    util_setup_spec_fetcher

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
    util_setup_fake_fetcher

    uri = "http://beta-gems.example.com/specs.#{@marshal_version}.gz"
    @fetcher.data[uri] = proc do
      raise Gem::RemoteFetcher::FetchError.new('it died', uri)
    end

    Gem::RemoteFetcher.fetcher = @fetcher

    @cmd.handle_options %w[--add http://beta-gems.example.com]

    util_setup_spec_fetcher

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
Error fetching http://beta-gems.example.com:
\tit died (#{uri})
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_add_bad_uri
    @cmd.handle_options %w[--add beta-gems.example.com]

    util_setup_spec_fetcher

    use_ui @ui do
      @cmd.execute
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

    util_setup_spec_fetcher

    fetcher = Gem::SpecFetcher.fetcher

    # HACK figure out how to force directory creation via fetcher
    #assert File.directory?(fetcher.dir), 'cache dir exists'

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF
*** Removed specs cache ***
    EOF

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    refute File.exist?(fetcher.dir), 'cache dir removed'
  end

  def test_execute_remove
    @cmd.handle_options %W[--remove #{@gem_repo}]

    util_setup_spec_fetcher

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal '', @ui.error
  end

  def test_execute_remove_no_network
    @cmd.handle_options %W[--remove #{@gem_repo}]

    util_setup_fake_fetcher

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

    util_setup_fake_fetcher
    source_index = util_setup_spec_fetcher @a1

    specs = source_index.map do |name, spec|
      [spec.name, spec.version, spec.original_platform]
    end

    @fetcher.data["#{@gem_repo}specs.#{Gem.marshal_version}.gz"] =
      util_gzip Marshal.dump(specs)

    latest_specs = source_index.latest_specs.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] =
      util_gzip Marshal.dump(latest_specs)

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "source cache successfully updated\n", @ui.output
    assert_equal '', @ui.error
  end

end

