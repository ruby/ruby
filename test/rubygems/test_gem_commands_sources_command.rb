# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/sources_command"

class TestGemCommandsSourcesCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::SourcesCommand.new

    @new_repo = "http://beta-gems.example.com"

    @old_https_proxy_config = Gem.configuration[:http_proxy]
  end

  def teardown
    Gem.configuration[:http_proxy] = @old_https_proxy_config

    super
  end

  def test_initialize_proxy
    assert @cmd.handles?(["--http-proxy", "http://proxy.example.com"])
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
    assert_equal "", @ui.error
  end

  def test_execute_add
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

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
    assert_equal "", @ui.error
  end

  def test_execute_add_allow_typo_squatting_source
    rubygems_org = "https://rubyems.org"

    spec_fetcher do |fetcher|
      fetcher.spec("a", 1)
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap(specs_dump_gz) do |io|
      Marshal.dump(specs, io)
    end

    @fetcher.data["#{rubygems_org}/specs.#{@marshal_version}.gz"] = specs_dump_gz.string
    @cmd.handle_options %W[--add #{rubygems_org}]
    ui = Gem::MockGemUi.new("y")

    use_ui ui do
      @cmd.execute
    end

    expected = "https://rubyems.org is too similar to https://rubygems.org\n\nDo you want to add this source? [yn]  https://rubyems.org added to sources\n"

    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_add_allow_typo_squatting_source_forced
    rubygems_org = "https://rubyems.org"

    spec_fetcher do |fetcher|
      fetcher.spec("a", 1)
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap(specs_dump_gz) do |io|
      Marshal.dump(specs, io)
    end

    @fetcher.data["#{rubygems_org}/specs.#{@marshal_version}.gz"] = specs_dump_gz.string
    @cmd.handle_options %W[--force --add #{rubygems_org}]

    @cmd.execute

    expected = "https://rubyems.org added to sources\n"
    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_add_deny_typo_squatting_source
    rubygems_org = "https://rubyems.org"

    spec_fetcher do |fetcher|
      fetcher.spec("a", 1)
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap(specs_dump_gz) do |io|
      Marshal.dump(specs, io)
    end

    @fetcher.data["#{rubygems_org}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

    @cmd.handle_options %W[--add #{rubygems_org}]

    ui = Gem::MockGemUi.new("n")

    use_ui ui do
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = "https://rubyems.org is too similar to https://rubygems.org\n\nDo you want to add this source? [yn]  "

    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    refute Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_add_nonexistent_source
    spec_fetcher

    uri = "http://beta-gems.example.com/specs.#{@marshal_version}.gz"
    @fetcher.data[uri] = proc do
      raise Gem::RemoteFetcher::FetchError.new("it died", uri)
    end

    @cmd.handle_options %w[--add http://beta-gems.example.com]

    use_ui @ui do
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = <<-EOF
Error fetching http://beta-gems.example.com:
\tit died (#{uri})
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add_existent_source_invalid_uri
    spec_fetcher

    uri = "https://u:p@example.com/specs.#{@marshal_version}.gz"

    @cmd.handle_options %w[--add https://u:p@example.com]
    @fetcher.data[uri] = proc do
      raise Gem::RemoteFetcher::FetchError.new("it died", uri)
    end

    use_ui @ui do
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = <<-EOF
Error fetching https://u:REDACTED@example.com:
\tit died (https://u:REDACTED@example.com/specs.#{@marshal_version}.gz)
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add_existent_source_invalid_uri_with_error_by_chance_including_the_uri_password
    spec_fetcher

    uri = "https://u:secret@example.com/specs.#{@marshal_version}.gz"

    @cmd.handle_options %w[--add https://u:secret@example.com]
    @fetcher.data[uri] = proc do
      raise Gem::RemoteFetcher::FetchError.new("it secretly died", uri)
    end

    use_ui @ui do
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = <<-EOF
Error fetching https://u:REDACTED@example.com:
\tit secretly died (https://u:REDACTED@example.com/specs.#{@marshal_version}.gz)
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add_redundant_source
    spec_fetcher

    @cmd.handle_options %W[--add #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EOF
source #{@gem_repo} already present in the cache
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add_redundant_source_trailing_slash
    spec_fetcher

    # Remove pre-existing gem source (w/ slash)
    repo_with_slash = "http://gems.example.com/"
    @cmd.handle_options %W[--remove #{repo_with_slash}]
    use_ui @ui do
      @cmd.execute
    end
    source = Gem::Source.new repo_with_slash
    assert_equal false, Gem.sources.include?(source)

    expected = <<-EOF
#{repo_with_slash} removed from sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error

    # Re-add pre-existing gem source (w/o slash)
    repo_without_slash = "http://gems.example.com"
    @cmd.handle_options %W[--add #{repo_without_slash}]
    use_ui @ui do
      @cmd.execute
    end
    source = Gem::Source.new repo_without_slash
    assert_equal true, Gem.sources.include?(source)

    expected = <<-EOF
http://gems.example.com/ removed from sources
http://gems.example.com added to sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error

    # Re-add original gem source (w/ slash)
    @cmd.handle_options %W[--add #{repo_with_slash}]
    use_ui @ui do
      @cmd.execute
    end
    source = Gem::Source.new repo_with_slash
    assert_equal true, Gem.sources.include?(source)

    expected = <<-EOF
http://gems.example.com/ removed from sources
http://gems.example.com added to sources
source http://gems.example.com/ already present in the cache
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add_http_rubygems_org
    http_rubygems_org = "http://rubygems.org/"

    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap specs_dump_gz do |io|
      Marshal.dump specs, io
    end

    @fetcher.data["#{http_rubygems_org}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

    @cmd.handle_options %W[--add #{http_rubygems_org}]

    ui = Gem::MockGemUi.new "n"

    use_ui ui do
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EXPECTED
    EXPECTED

    assert_equal expected, @ui.output
    assert_empty @ui.error
  end

  def test_execute_add_http_rubygems_org_forced
    rubygems_org = "http://rubygems.org"

    spec_fetcher do |fetcher|
      fetcher.spec("a", 1)
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap(specs_dump_gz) do |io|
      Marshal.dump(specs, io)
    end

    @fetcher.data["#{rubygems_org}/specs.#{@marshal_version}.gz"] = specs_dump_gz.string
    @cmd.handle_options %W[--force --add #{rubygems_org}]

    @cmd.execute

    expected = "http://rubygems.org added to sources\n"
    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_add_https_rubygems_org
    https_rubygems_org = "https://rubygems.org/"

    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    specs = Gem::Specification.map do |spec|
      [spec.name, spec.version, spec.original_platform]
    end

    specs_dump_gz = StringIO.new
    Zlib::GzipWriter.wrap specs_dump_gz do |io|
      Marshal.dump specs, io
    end

    @fetcher.data["#{https_rubygems_org}/specs.#{@marshal_version}.gz"] =
      specs_dump_gz.string

    @cmd.handle_options %W[--add #{https_rubygems_org}]

    ui = Gem::MockGemUi.new "n"

    use_ui ui do
      assert_raise Gem::MockGemUi::TermError do
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
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EOF
beta-gems.example.com is not a URI
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
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
    assert_equal "", @ui.error

    dir = Gem.spec_cache_dir
    refute File.exist?(dir), "cache dir removed"
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
    assert_equal "", @ui.error
  end

  def test_execute_remove
    @cmd.handle_options %W[--remove #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_remove_no_network
    spec_fetcher

    @cmd.handle_options %W[--remove #{@gem_repo}]

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_update
    @cmd.handle_options %w[--update]

    spec_fetcher do |fetcher|
      fetcher.gem "a", 1
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "source cache successfully updated\n", @ui.output
    assert_equal "", @ui.error
  end
end
