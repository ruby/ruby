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
*** NO CONFIGURED SOURCES, DEFAULT SOURCES LISTED BELOW ***

#{@gem_repo}
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add
    setup_fake_source(@new_repo)

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

  def test_execute_append
    setup_fake_source(@new_repo)

    @cmd.handle_options %W[--append #{@new_repo}]

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

    setup_fake_source(rubygems_org)

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

  def test_execute_append_allow_typo_squatting_source
    rubygems_org = "https://rubyems.org"

    setup_fake_source(rubygems_org)

    @cmd.handle_options %W[--append #{rubygems_org}]
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

    setup_fake_source(rubygems_org)

    @cmd.handle_options %W[--force --add #{rubygems_org}]

    @cmd.execute

    expected = "https://rubyems.org added to sources\n"
    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_append_allow_typo_squatting_source_forced
    rubygems_org = "https://rubyems.org"

    setup_fake_source(rubygems_org)

    @cmd.handle_options %W[--force --append #{rubygems_org}]

    @cmd.execute

    expected = "https://rubyems.org added to sources\n"
    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_add_deny_typo_squatting_source
    rubygems_org = "https://rubyems.org"

    setup_fake_source(rubygems_org)

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

  def test_execute_append_deny_typo_squatting_source
    rubygems_org = "https://rubyems.org"

    setup_fake_source(rubygems_org)

    @cmd.handle_options %W[--append #{rubygems_org}]

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

  def test_execute_append_nonexistent_source
    spec_fetcher

    uri = "http://beta-gems.example.com/specs.#{@marshal_version}.gz"
    @fetcher.data[uri] = proc do
      raise Gem::RemoteFetcher::FetchError.new("it died", uri)
    end

    @cmd.handle_options %w[--append http://beta-gems.example.com]

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

  def test_execute_append_existent_source_invalid_uri
    spec_fetcher

    uri = "https://u:p@example.com/specs.#{@marshal_version}.gz"

    @cmd.handle_options %w[--append https://u:p@example.com]
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

  def test_execute_append_existent_source_invalid_uri_with_error_by_chance_including_the_uri_password
    spec_fetcher

    uri = "https://u:secret@example.com/specs.#{@marshal_version}.gz"

    @cmd.handle_options %w[--append https://u:secret@example.com]
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

  def test_execute_append_redundant_source
    spec_fetcher

    @cmd.handle_options %W[--append #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal [@gem_repo], Gem.sources

    expected = <<-EOF
#{@gem_repo} moved to end of sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_add_redundant_source_trailing_slash
    repo_with_slash = "http://sample.repo/"

    Gem.configuration.sources = [repo_with_slash]

    setup_fake_source(repo_with_slash)

    # Re-add pre-existing gem source (w/o slash)
    repo_without_slash = repo_with_slash.delete_suffix("/")
    @cmd.handle_options %W[--add #{repo_without_slash}]
    use_ui @ui do
      @cmd.execute
    end
    source = Gem::Source.new repo_without_slash
    assert_equal true, Gem.sources.include?(source)

    expected = <<-EOF
source #{repo_without_slash} already present in the cache
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
source #{repo_without_slash} already present in the cache
source #{repo_with_slash} already present in the cache
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.configuration.sources = nil
  end

  def test_execute_add_http_rubygems_org
    http_rubygems_org = "http://rubygems.org/"

    setup_fake_source(http_rubygems_org)

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

  def test_execute_append_http_rubygems_org
    http_rubygems_org = "http://rubygems.org/"

    setup_fake_source(http_rubygems_org)

    @cmd.handle_options %W[--append #{http_rubygems_org}]

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

    setup_fake_source(rubygems_org)

    @cmd.handle_options %W[--force --add #{rubygems_org}]

    @cmd.execute

    expected = "http://rubygems.org added to sources\n"
    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_append_http_rubygems_org_forced
    rubygems_org = "http://rubygems.org"

    setup_fake_source(rubygems_org)

    @cmd.handle_options %W[--force --append #{rubygems_org}]

    @cmd.execute

    expected = "http://rubygems.org added to sources\n"
    assert_equal expected, ui.output

    source = Gem::Source.new(rubygems_org)
    assert Gem.sources.include?(source)

    assert_empty ui.error
  end

  def test_execute_add_https_rubygems_org
    https_rubygems_org = "https://rubygems.org/"

    setup_fake_source(https_rubygems_org)

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

  def test_execute_append_https_rubygems_org
    https_rubygems_org = "https://rubygems.org/"

    setup_fake_source(https_rubygems_org)

    @cmd.handle_options %W[--append #{https_rubygems_org}]

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

  def test_execute_append_bad_uri
    @cmd.handle_options %w[--append beta-gems.example.com]

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
*** NO CONFIGURED SOURCES, DEFAULT SOURCES LISTED BELOW ***

#{@gem_repo}
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_remove
    Gem.configuration.sources = [@new_repo]

    setup_fake_source(@new_repo)

    @cmd.handle_options %W[--remove #{@new_repo}]

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@new_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.configuration.sources = nil
  end

  def test_execute_remove_no_network
    Gem.configuration.sources = [@new_repo]

    spec_fetcher

    @cmd.handle_options %W[--remove #{@new_repo}]

    @fetcher.data["#{@new_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@new_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.configuration.sources = nil
  end

  def test_execute_remove_not_present
    Gem.configuration.sources = ["https://other.repo"]

    @cmd.handle_options %W[--remove #{@new_repo}]

    use_ui @ui do
      @cmd.execute
    end

    expected = "source #{@new_repo} cannot be removed because it's not present in #{Gem.configuration.config_file_name}\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.configuration.sources = nil
  end

  def test_execute_remove_nothing_configured
    spec_fetcher

    @cmd.handle_options %W[--remove https://does.not.exist]

    use_ui @ui do
      @cmd.execute
    end

    expected = "source https://does.not.exist cannot be removed because there are no configured sources in #{Gem.configuration.config_file_name}\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_remove_default_also_present_in_configuration
    Gem.configuration.sources = [@gem_repo]

    @cmd.handle_options %W[--remove #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    expected = "WARNING:  Removing a default source when it is the only source has no effect. Add a different source to #{Gem.configuration.config_file_name} if you want to stop using it as a source.\n"

    assert_equal "", @ui.output
    assert_equal expected, @ui.error
  ensure
    Gem.configuration.sources = nil
  end

  def test_remove_default_also_present_in_configuration_when_there_are_more_configured_sources
    Gem.configuration.sources = [@gem_repo, "https://other.repo"]

    @cmd.handle_options %W[--remove #{@gem_repo}]

    use_ui @ui do
      @cmd.execute
    end

    expected = "#{@gem_repo} removed from sources\n"

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.configuration.sources = nil
  end

  def test_execute_remove_redundant_source_trailing_slash
    repo_with_slash = "http://sample.repo/"

    Gem.configuration.sources = [repo_with_slash]

    setup_fake_source(repo_with_slash)

    repo_without_slash = repo_with_slash.delete_suffix("/")

    @cmd.handle_options %W[--remove #{repo_without_slash}]
    use_ui @ui do
      @cmd.execute
    end
    source = Gem::Source.new repo_without_slash
    assert_equal false, Gem.sources.include?(source)

    expected = <<-EOF
#{repo_without_slash} removed from sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  ensure
    Gem.configuration.sources = nil
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

  def test_execute_prepend_new_source
    setup_fake_source(@new_repo)

    @cmd.handle_options %W[--prepend #{@new_repo}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal [@new_repo, @gem_repo], Gem.sources

    expected = <<-EOF
#{@new_repo} added to sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_prepend_existing_source
    setup_fake_source(@new_repo)

    # Append the source normally first
    @cmd.handle_options %W[--append #{@new_repo}]
    use_ui @ui do
      @cmd.execute
    end

    # Initial state: [@gem_repo, @new_repo]
    assert_equal [@gem_repo, @new_repo], Gem.sources

    # Now prepend the existing source
    @cmd.handle_options %W[--prepend #{@new_repo}]
    use_ui @ui do
      @cmd.execute
    end

    # Should be moved to front: [@new_repo, @gem_repo]
    assert_equal [@new_repo, @gem_repo], Gem.sources

    expected = <<-EOF
#{@new_repo} added to sources
#{@new_repo} moved to top of sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_append_existing_source
    setup_fake_source(@new_repo)

    # Prepend the source first so it's at the beginning
    @cmd.handle_options %W[--prepend #{@new_repo}]
    use_ui @ui do
      @cmd.execute
    end

    # Initial state: [@new_repo, @gem_repo] (new_repo is first)
    assert_equal [@new_repo, @gem_repo], Gem.sources

    # Now append the existing source
    @cmd.handle_options %W[--append #{@new_repo}]
    use_ui @ui do
      @cmd.execute
    end

    # Should be moved to end: [@gem_repo, @new_repo]
    assert_equal [@gem_repo, @new_repo], Gem.sources

    expected = <<-EOF
#{@new_repo} added to sources
#{@new_repo} moved to end of sources
    EOF

    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  private

  def setup_fake_source(uri)
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

    @fetcher.data["#{uri}/specs.#{@marshal_version}.gz"] = specs_dump_gz.string
  end
end
