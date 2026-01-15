# frozen_string_literal: true

require_relative "helper"
require "rubygems/package"
require "rubygems/security"
require "rubygems/commands/fetch_command"

class TestGemCommandsFetchCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::FetchCommand.new
  end

  def test_execute
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 2
    end

    assert_path_not_exist File.join(@tempdir, "cache"), "sanity check"

    @cmd.options[:args] = %w[a]

    execute_with_exit_code

    a2 = specs["a-2"]

    assert_path_exist(File.join(@tempdir, a2.file_name),
                       "#{a2.full_name} not fetched")
    assert_path_not_exist File.join(@tempdir, "cache"),
                       "gem repository directories must not be created"
  end

  def test_execute_latest
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 1
      fetcher.gem "a", 2
    end

    assert_path_not_exist File.join(@tempdir, "cache"), "sanity check"

    @cmd.options[:args] = %w[a]
    @cmd.options[:version] = req(">= 0.1")

    execute_with_exit_code

    a2 = specs["a-2"]
    assert_path_exist(File.join(@tempdir, a2.file_name),
                       "#{a2.full_name} not fetched")
    assert_path_not_exist File.join(@tempdir, "cache"),
                       "gem repository directories must not be created"
  end

  def test_execute_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 2
      fetcher.gem "a", "2.a"
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:prerelease] = true

    execute_with_exit_code

    a2 = specs["a-2"]

    assert_path_exist(File.join(@tempdir, a2.file_name),
                       "#{a2.full_name} not fetched")
  end

  def test_execute_platform
    a2_spec, a2 = util_gem("a", "2")

    a2_universal_darwin_spec, a2_universal_darwin = util_gem("a", "2") do |s|
      s.platform = "universal-darwin"
    end

    Gem::RemoteFetcher.fetcher = @fetcher = Gem::FakeFetcher.new

    write_marshalled_gemspecs(a2_spec, a2_universal_darwin_spec)

    @cmd.options[:args] = %w[a]

    @fetcher.data["#{@gem_repo}latest_specs.#{Gem.marshal_version}.gz"] = util_gzip(Marshal.dump([
      Gem::NameTuple.new(a2_spec.name, a2_spec.version, a2_spec.platform),
      Gem::NameTuple.new(a2_universal_darwin_spec.name, a2_universal_darwin_spec.version, a2_universal_darwin_spec.platform),
    ]))

    @fetcher.data["#{@gem_repo}gems/#{a2_spec.file_name}"] = Gem.read_binary(a2)
    FileUtils.cp a2, a2_spec.cache_file

    @fetcher.data["#{@gem_repo}gems/#{a2_universal_darwin_spec.file_name}"] = Gem.read_binary(a2_universal_darwin)
    FileUtils.cp a2_universal_darwin, a2_universal_darwin_spec.cache_file

    util_set_arch "arm64-darwin20" do
      execute_with_exit_code
    end

    assert_path_exist(File.join(@tempdir, a2_universal_darwin_spec.file_name),
                       "#{a2_universal_darwin_spec.full_name} not fetched")
  end

  def test_execute_specific_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 2
      fetcher.gem "a", "2.a"
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:prerelease] = true
    @cmd.options[:version] = "2.a"

    execute_with_exit_code

    a2_pre = specs["a-2.a"]

    assert_path_exist(File.join(@tempdir, a2_pre.file_name),
                       "#{a2_pre.full_name} not fetched")
  end

  def test_execute_version
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 1
      fetcher.gem "a", 2
    end

    @cmd.options[:args] = %w[a]
    @cmd.options[:version] = Gem::Requirement.new "1"

    execute_with_exit_code

    a1 = specs["a-1"]

    assert_path_exist(File.join(@tempdir, a1.file_name),
                       "#{a1.full_name} not fetched")
  end

  def test_execute_version_specified_by_colon
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 1
    end

    @cmd.options[:args] = %w[a:1]

    execute_with_exit_code

    a1 = specs["a-1"]

    assert_path_exist(File.join(@tempdir, a1.file_name),
                       "#{a1.full_name} not fetched")
  end

  def test_execute_two_version
    @cmd.options[:args] = %w[a b]
    @cmd.options[:version] = Gem::Requirement.new "1"

    execute_with_term_error

    msg = "ERROR:  Can't use --version with multiple gems. You can specify multiple gems with" \
      " version requirements using `gem fetch 'my_gem:1.0.0' 'my_other_gem:~>2.0.0'`"

    assert_empty @ui.output
    assert_equal msg, @ui.error.chomp
  end

  def test_execute_two_version_specified_by_colon
    specs = spec_fetcher do |fetcher|
      fetcher.gem "a", 1
      fetcher.gem "b", 1
    end

    @cmd.options[:args] = %w[a:1 b:1]

    execute_with_exit_code

    a1 = specs["a-1"]
    b1 = specs["b-1"]

    assert_path_exist(File.join(@tempdir, a1.file_name),
                       "#{a1.full_name} not fetched")
    assert_path_exist(File.join(@tempdir, b1.file_name),
                       "#{b1.full_name} not fetched")
  end

  def test_execute_version_nonexistent
    spec_fetcher do |fetcher|
      fetcher.spec "foobar", 1
    end

    @cmd.options[:args] = %w[foobar:2]

    execute_with_term_error

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'foobar' (2) in any repository
ERROR:  Possible alternatives: foobar
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_execute_nonexistent_hint_disabled
    spec_fetcher do |fetcher|
      fetcher.spec "foobar", 1
    end

    @cmd.options[:args] = %w[foobar:2]
    @cmd.options[:suggest_alternate] = false

    execute_with_term_error

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'foobar' (2) in any repository
    EXPECTED

    assert_equal expected, @ui.error
  end

  private

  def execute_with_term_error
    use_ui @ui do
      assert_raise Gem::MockGemUi::TermError, @ui.error do
        @cmd.execute
      end
    end
  end

  def execute_with_exit_code
    use_ui @ui do
      Dir.chdir @tempdir do
        assert_raise Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      end
    end
  end
end
