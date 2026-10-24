# frozen_string_literal: true

require_relative "helper"
require_relative "multifactor_auth_utilities"
require "rubygems/commands/push_command"
require "rubygems/config_file"

class TestGemCommandsPushCommand < Gem::TestCase
  def setup
    super

    credential_setup

    ENV["RUBYGEMS_HOST"] = nil
    Gem.host = Gem::DEFAULT_HOST
    Gem.configuration.disable_default_gem_server = false

    @gems_dir  = File.join @tempdir, "gems"
    @cache_dir = File.join @gemhome, "cache"

    FileUtils.mkdir @gems_dir

    Gem.configuration.rubygems_api_key =
      "ed244fbf2b1a52e012da8616c512fa47f9aa5250"

    @spec, @path = util_gem "freewill", "1.0.0"
    @host = "https://rubygems.example"
    @api_key = Gem.configuration.rubygems_api_key

    @fetcher = Gem::MultifactorAuthFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    @cmd = Gem::Commands::PushCommand.new

    singleton_gem_class.class_eval do
      alias_method :orig_latest_rubygems_version, :latest_rubygems_version

      def latest_rubygems_version
        Gem.rubygems_version
      end
    end
  end

  def teardown
    credential_teardown

    super

    singleton_gem_class.class_eval do
      remove_method :latest_rubygems_version
      alias_method :latest_rubygems_version, :orig_latest_rubygems_version
    end
  end

  def send_battery
    use_ui @ui do
      @cmd.instance_variable_set :@host, @host
      @cmd.send_gem(@path)
    end

    assert_match(/Pushing gem to #{@host}.../, @ui.output)

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal File.size(@path), @fetcher.last_request["Content-Length"].to_i
    assert_equal "application/octet-stream", @fetcher.last_request["Content-Type"]
    assert_equal @api_key, @fetcher.last_request["Authorization"]

    assert_match @response, @ui.output
  end

  def test_execute
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [@path]

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_execute_host
    host = "https://other.example"

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")
    @fetcher.data["#{Gem.host}/api/v1/gems"] =
      ["fail", 500, "Internal Server Error"]

    @cmd.options[:host] = host
    @cmd.options[:args] = [@path]

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_handle_options_platform_and_ruby_abi
    @cmd.handle_options %w[--platform arm64-darwin --ruby-abi 3.4 demo.gem]

    assert_equal "arm64-darwin", @cmd.options[:platform]
    assert_equal "3.4", @cmd.options[:ruby_abi]
    assert_equal ["demo.gem"], @cmd.options[:args]
  end

  def test_execute_with_platform_selector_selects_matching_gem
    _, matching_path = util_gem "platform-match", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/platform-match.rb"]
      spec.platform = "arm64-darwin"
    end
    _, other_path = util_gem "platform-other", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/platform-other.rb"]
      spec.platform = "x86_64-linux"
    end

    @response = "Successfully registered gem: platform-match (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [other_path, matching_path]
    @cmd.options[:platform] = "arm64-darwin"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(matching_path), @fetcher.last_request.body
  end

  def test_execute_with_ruby_selector_selects_matching_gem
    _, other_path = util_gem "ruby-other", "1.0.0", ruby_abi: "3.3" do |spec|
      spec.files = ["lib/ruby-other.rb"]
      spec.platform = "arm64-darwin"
    end
    _, matching_path = util_gem "ruby-match", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ruby-match.rb"]
      spec.platform = "arm64-darwin"
    end

    @response = "Successfully registered gem: ruby-match (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [other_path, matching_path]
    @cmd.options[:ruby_abi] = "3.4"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(matching_path), @fetcher.last_request.body
  end

  def test_execute_with_selectors_skips_invalid_gem_package
    invalid_path = File.join @tempdir, "invalid.gem"
    File.binwrite invalid_path, "not a gem"
    _, matching_path = util_gem "skip-invalid", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/skip-invalid.rb"]
      spec.platform = "arm64-darwin"
    end

    @response = "Successfully registered gem: skip-invalid (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [invalid_path, matching_path]
    @cmd.options[:platform] = "arm64-darwin"

    use_ui @ui do
      @cmd.execute
    end

    assert_match(/Skipping #{Regexp.escape(invalid_path)}: package metadata is missing/, @ui.error)
    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(matching_path), @fetcher.last_request.body
  end

  def test_execute_with_platform_and_ruby_selectors_selects_matching_gem
    _, wrong_platform_path = util_gem "both-wrong-platform", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/both-wrong-platform.rb"]
      spec.platform = "x86_64-linux"
    end
    _, wrong_ruby_path = util_gem "both-wrong-ruby", "1.0.0", ruby_abi: "3.3" do |spec|
      spec.files = ["lib/both-wrong-ruby.rb"]
      spec.platform = "arm64-darwin"
    end
    _, matching_path = util_gem "both-match", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/both-match.rb"]
      spec.platform = "arm64-darwin"
    end

    @response = "Successfully registered gem: both-match (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [wrong_platform_path, wrong_ruby_path, matching_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(matching_path), @fetcher.last_request.body
  end

  def test_execute_with_same_name_version_platform_selects_matching_ruby_abi
    _, ruby_33_path = util_gem "same-target", "1.0.0", ruby_abi: "3.3" do |spec|
      spec.files = ["lib/same-target.rb"]
      spec.platform = "arm64-darwin"
    end
    _, ruby_34_path = util_gem "same-target", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/same-target.rb"]
      spec.platform = "arm64-darwin"
    end

    @response = "Successfully registered gem: same-target (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [ruby_33_path, ruby_34_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(ruby_34_path), @fetcher.last_request.body
  end

  def test_execute_with_non_and_content_addressable_candidates_selects_content_addressable_for_ruby_abi
    _, non_content_addressable_path = util_gem "mixed-target", "1.0.0" do |spec|
      spec.platform = "arm64-darwin"
      spec.required_ruby_version = ">= 3.1"
    end
    _, content_addressable_path = util_gem "mixed-target", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/mixed-target.rb"]
      spec.platform = "arm64-darwin"
    end

    @response = "Successfully registered gem: mixed-target (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [non_content_addressable_path, content_addressable_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(content_addressable_path), @fetcher.last_request.body
  end

  def test_execute_with_ruby_abi_selector_does_not_match_non_content_addressable_ruby_requirement
    _, gem_path = util_gem "non-content-addressable-ruby", "1.0.0" do |spec|
      spec.platform = "arm64-darwin"
      spec.required_ruby_version = ">= 3.1"
    end

    @cmd.options[:args] = [gem_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_equal "No gem matched platform arm64-darwin and Ruby ABI 3.4", error.message
  end

  def test_execute_with_selectors_raises_when_no_gems_match
    _, gem_path = util_gem "no-match", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/no-match.rb"]
      spec.platform = "arm64-darwin"
    end

    @cmd.options[:args] = [gem_path]
    @cmd.options[:platform] = "x86_64-linux"
    @cmd.options[:ruby_abi] = "3.4"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_equal "No gem matched platform x86_64-linux and Ruby ABI 3.4", error.message
  end

  def test_execute_with_selectors_raises_when_multiple_gems_match
    _, first_path = util_gem "ambiguous-one", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ambiguous-one.rb"]
      spec.platform = "arm64-darwin"
    end
    _, second_path = util_gem "ambiguous-two", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ambiguous-two.rb"]
      spec.platform = "arm64-darwin"
    end

    @cmd.options[:args] = [first_path, second_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_match "Multiple gems matched platform arm64-darwin and Ruby ABI 3.4", error.message
    assert_match first_path, error.message
    assert_match second_path, error.message
  end

  def test_execute_with_platform_selector_raises_when_multiple_ruby_abis_match
    _, ruby_33_path = util_gem "ambiguous-target", "1.0.0", ruby_abi: "3.3" do |spec|
      spec.files = ["lib/ambiguous-target.rb"]
      spec.platform = "arm64-darwin"
    end
    _, ruby_34_path = util_gem "ambiguous-target", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ambiguous-target.rb"]
      spec.platform = "arm64-darwin"
    end

    @cmd.options[:args] = [ruby_33_path, ruby_34_path]
    @cmd.options[:platform] = "arm64-darwin"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_match "Multiple gems matched platform arm64-darwin", error.message
    assert_match ruby_33_path, error.message
    assert_match ruby_34_path, error.message
    assert_match "Specify --ruby-abi with one of: 3.3, 3.4", error.message
  end

  def test_execute_with_ruby_abi_selector_raises_when_multiple_platforms_match
    _, arm_path = util_gem "ambiguous-platform", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ambiguous-platform.rb"]
      spec.platform = "arm64-darwin"
    end
    _, linux_path = util_gem "ambiguous-platform", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ambiguous-platform.rb"]
      spec.platform = "x86_64-linux"
    end

    @cmd.options[:args] = [arm_path, linux_path]
    @cmd.options[:ruby_abi] = "3.4"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_match "Multiple gems matched Ruby ABI 3.4", error.message
    assert_match arm_path, error.message
    assert_match linux_path, error.message
    assert_match "Specify --platform with one of: arm64-darwin, x86_64-linux", error.message
  end

  def test_execute_with_platform_selector_suggests_exact_filename_for_gem_without_ruby_abi
    _, non_content_addressable_path = util_gem "ambiguous-non-content-addressable", "1.0.0" do |spec|
      spec.platform = "arm64-darwin"
      spec.required_ruby_version = ">= 3.1"
    end
    _, content_addressable_path = util_gem "ambiguous-non-content-addressable", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/ambiguous-non-content-addressable.rb"]
      spec.platform = "arm64-darwin"
    end

    @cmd.options[:args] = [non_content_addressable_path, content_addressable_path]
    @cmd.options[:platform] = "arm64-darwin"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_match "Multiple gems matched platform arm64-darwin", error.message
    assert_match non_content_addressable_path, error.message
    assert_match content_addressable_path, error.message
    assert_match "Specify --ruby-abi with one of: 3.4", error.message
    assert_match "To push a gem without a Ruby ABI, pass the exact filename.", error.message
  end

  def test_execute_without_selectors_still_rejects_multiple_gems
    _, other_path = util_gem "extra-gem", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/extra-gem.rb"]
      spec.platform = "arm64-darwin"
    end

    @cmd.options[:args] = [@path, other_path]

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_match "Too many gem names", error.message
  end

  def test_execute_with_both_selectors_raises_when_multiple_gems_match_without_suggestion
    _, first_path = util_gem "dual-ambiguous-one", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/dual-ambiguous-one.rb"]
      spec.platform = "arm64-darwin"
    end
    _, second_path = util_gem "dual-ambiguous-two", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/dual-ambiguous-two.rb"]
      spec.platform = "arm64-darwin"
    end

    @cmd.options[:args] = [first_path, second_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    error = assert_raise Gem::CommandLineError do
      @cmd.execute
    end

    assert_match "Multiple gems matched platform arm64-darwin and Ruby ABI 3.4", error.message
    assert_match first_path, error.message
    assert_match second_path, error.message
    refute_match(/Specify/, error.message)
  end

  def test_execute_with_both_selectors_selects_single_matching_gem
    _, matching_path = util_gem "dual-match", "1.0.0", ruby_abi: "3.4" do |spec|
      spec.files = ["lib/dual-match.rb"]
      spec.platform = "arm64-darwin"
    end

    @response = "Successfully registered gem: dual-match (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [matching_path]
    @cmd.options[:platform] = "arm64-darwin"
    @cmd.options[:ruby_abi] = "3.4"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(matching_path), @fetcher.last_request.body
  end

  def test_execute_with_platform_selector_selects_single_non_content_addressable_gem
    _, non_content_addressable_path = util_gem "non-content-addressable-only", "1.0.0" do |spec|
      spec.platform = "arm64-darwin"
      spec.required_ruby_version = ">= 3.1"
    end

    @response = "Successfully registered gem: non-content-addressable-only (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [non_content_addressable_path]
    @cmd.options[:platform] = "arm64-darwin"

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(non_content_addressable_path), @fetcher.last_request.body
  end

  def test_execute_with_ruby_abi_selector_rejects_source_gem
    _, source_path = util_gem "source-ruby", "1.0.0" do |spec|
      spec.files = ["lib/source-ruby.rb"]
      spec.required_ruby_version = "~> 3.4.0"
    end

    @response = "Successfully registered gem: source-ruby (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [source_path]
    @cmd.options[:ruby_abi] = "3.4"

    error = assert_raise(Gem::CommandLineError) do
      @cmd.execute
    end

    assert_match(/No gem matched/, error.message)
  end

  def test_execute_attestation
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    File.write("#{@path}.sigstore.json", '{"attestation":true}')
    @cmd.options[:args] = [@path]
    @cmd.options[:attestations] = ["#{@path}.sigstore.json"]

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    content_length = @fetcher.last_request["Content-Length"].to_i
    assert_equal content_length, @fetcher.last_request.body.length
    assert_attestation_multipart Gem.read_binary("#{@path}.sigstore.json")
  end

  def test_execute_attestation_multiple
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    File.write("#{@path}.a.sigstore.json", '{"attestation":"a"}')
    File.write("#{@path}.b.sigstore.json", '{"attestation":"b"}')
    @cmd.options[:args] = [@path]
    @cmd.options[:attestations] = ["#{@path}.a.sigstore.json", "#{@path}.b.sigstore.json"]

    @cmd.execute

    assert_attestation_multipart '{"attestation":"a"},{"attestation":"b"}'
  end

  def test_execute_attestation_auto
    omit if RUBY_ENGINE == "jruby"

    ENV["GITHUB_ACTIONS"] = "true"

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    attestation_content = '{"auto":"attestation"}'
    @cmd.options[:args] = [@path]

    @cmd.stub(:attest!, attestation_content) do
      @cmd.execute
    end

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    content_length = @fetcher.last_request["Content-Length"].to_i
    assert_equal content_length, @fetcher.last_request.body.length
    assert_attestation_multipart attestation_content
  end

  def test_execute_attestation_fallback
    omit if RUBY_ENGINE == "jruby"

    ENV["GITHUB_ACTIONS"] = "true"

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [@path]

    @cmd.stub(:attest!, proc { raise Gem::Exception, "boom" }) do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match "Failed to create an attestation, pushing without one.", @ui.error
    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_execute_attestation_explicit_missing_file
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: "", code: 200, msg: "OK")

    @cmd.options[:args] = [@path]
    @cmd.options[:attestations] = ["#{@path}.sigstore.json"]

    e = assert_raise Gem::Exception do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match "Failed to read attestation", e.message
    refute_match "pushing without one", @ui.error
    assert_nil @fetcher.last_request
  end

  def test_execute_attestation_explicit_invalid_json
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: "", code: 200, msg: "OK")

    File.write("#{@path}.sigstore.json", "not json")
    @cmd.options[:args] = [@path]
    @cmd.options[:attestations] = ["#{@path}.sigstore.json"]

    e = assert_raise Gem::Exception do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match "is not valid JSON", e.message
    refute_match "pushing without one", @ui.error
    assert_nil @fetcher.last_request
  end

  def test_execute_attestation_explicit_json_scalar
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: "", code: 200, msg: "OK")

    File.write("#{@path}.sigstore.json", "null")
    @cmd.options[:args] = [@path]
    @cmd.options[:attestations] = ["#{@path}.sigstore.json"]

    e = assert_raise Gem::Exception do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_match "is not a JSON object", e.message
    assert_nil @fetcher.last_request
  end

  def test_execute_attestation_network_error_not_retried_without_attestation
    omit if RUBY_ENGINE == "jruby"

    ENV["GITHUB_ACTIONS"] = "true"

    requests = 0
    @fetcher.data["#{Gem.host}/api/v1/gems"] = proc do
      requests += 1
      raise Gem::RemoteFetcher::FetchError.new("timed out", "#{Gem.host}/api/v1/gems")
    end

    @cmd.options[:args] = [@path]

    assert_raise Gem::RemoteFetcher::FetchError do
      @cmd.stub(:attest!, '{"auto":"attestation"}') do
        use_ui @ui do
          @cmd.execute
        end
      end
    end

    assert_equal 1, requests
    refute_match "pushing without one", @ui.error
  end

  def test_execute_attestation_auto_skipped_unless_github_actions_true
    omit if RUBY_ENGINE == "jruby"

    ENV["GITHUB_ACTIONS"] = "false"

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [@path]

    attest_called = false
    @cmd.stub(:attest!, proc { attest_called = true }) do
      @cmd.execute
    end

    refute attest_called, "attest! should not be called when GITHUB_ACTIONS is not \"true\""
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_execute_attestation_skipped_on_non_rubygems_host
    omit if RUBY_ENGINE == "jruby"

    ENV["GITHUB_ACTIONS"] = "true"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = "https://privategemserver.example"
    end

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@spec.metadata["allowed_push_host"]}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [@path]

    attest_called = false
    @cmd.stub(:attest!, proc { attest_called = true }) do
      @cmd.execute
    end

    refute attest_called, "attest! should not be called for non-rubygems.org hosts"
    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_execute_attestation_skipped_on_jruby
    ENV["GITHUB_ACTIONS"] = "true"

    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    @cmd.options[:args] = [@path]

    attest_called = false
    engine = RUBY_ENGINE
    Object.send :remove_const, :RUBY_ENGINE
    Object.const_set :RUBY_ENGINE, "jruby"

    begin
      @cmd.stub(:attest!, proc { attest_called = true }) do
        @cmd.execute
      end

      refute attest_called, "attest! should not be called on JRuby"
      assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
      assert_equal Gem.read_binary(@path), @fetcher.last_request.body
      assert_equal "application/octet-stream",
                   @fetcher.last_request["Content-Type"]
    ensure
      Object.send :remove_const, :RUBY_ENGINE
      Object.const_set :RUBY_ENGINE, engine
    end
  end

  # When the running Ruby lives under a path containing whitespace, Gem.ruby
  # returns a quoted string. That quoting must not leak into the argv passed to
  # Open3.capture2e, or signing spawns fail and push silently falls back to an
  # unsigned upload.
  def test_attest_unquotes_ruby
    require "open3"

    fake_status = Object.new
    def fake_status.success?
      true
    end

    captured = nil
    capture_stub = lambda do |*args, **_kwargs|
      captured = args
      File.write(args[args.index("--bundle") + 1], "{}")
      ["", fake_status]
    end
    Gem.stub(:ruby, '"/path with space/bin/ruby"') do
      Open3.stub(:capture2e, capture_stub) do
        @cmd.send(:attest!, @path)
      end
    end

    refute_nil captured, "signing command should have been spawned"
    # captured[0] is the env hash; the interpreter follows it.
    assert_equal "/path with space/bin/ruby", captured[1]
    refute_includes captured[1], '"'
    assert_equal "-S", captured[2]
  end

  def test_attest_aborts_when_signing_fails
    require "open3"

    fake_status = Object.new
    def fake_status.success?
      false
    end

    bundle_path = nil
    capture_stub = lambda do |*args, **_kwargs|
      bundle_path = args[args.index("--bundle") + 1]
      ["sigstore-cli: no identity token available", fake_status]
    end

    e = assert_raise Gem::Exception do
      Open3.stub(:capture2e, capture_stub) do
        @cmd.send(:attest!, @path)
      end
    end

    assert_match "Failed to sign gem", e.message
    assert_match "no identity token available", e.message
    refute_nil bundle_path, "signing command should have been spawned"
    refute File.exist?(bundle_path), "bundle tempfile should be removed"
  end

  def test_attest_rejects_a_bundle_that_is_not_json
    require "open3"

    fake_status = Object.new
    def fake_status.success?
      true
    end

    capture_stub = lambda do |*args, **_kwargs|
      File.write(args[args.index("--bundle") + 1], "not json")
      ["", fake_status]
    end

    e = assert_raise Gem::Exception do
      Open3.stub(:capture2e, capture_stub) do
        @cmd.send(:attest!, @path)
      end
    end

    assert_match "is not valid JSON", e.message
  end

  def test_attest_returns_bundle_content_and_removes_tempfile
    require "open3"

    fake_status = Object.new
    def fake_status.success?
      true
    end

    bundle_path = nil
    capture_stub = lambda do |*args, **_kwargs|
      bundle_path = args[args.index("--bundle") + 1]
      File.write(bundle_path, '{"signed":true}')
      ["", fake_status]
    end

    content = Open3.stub(:capture2e, capture_stub) do
      @cmd.send(:attest!, @path)
    end

    assert_equal '{"signed":true}', content
    refute File.exist?(bundle_path), "bundle tempfile should be removed"
  end

  def test_execute_allowed_push_host
    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = "https://privategemserver.example"
    end

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@spec.metadata["allowed_push_host"]}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")
    @fetcher.data["#{Gem.host}/api/v1/gems"] =
      ["fail", 500, "Internal Server Error"]

    @cmd.options[:args] = [@path]

    @cmd.execute

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal "application/octet-stream",
                 @fetcher.last_request["Content-Type"]
  end

  def test_sending_when_default_host_disabled
    Gem.configuration.disable_default_gem_server = true
    response = "You must specify a gem server"

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @ui.error
  end

  def test_sending_when_default_host_disabled_with_override
    ENV["RUBYGEMS_HOST"] = @host
    Gem.configuration.disable_default_gem_server = true
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    send_battery
  end

  def test_sending_gem_to_metadata_host
    @host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["default_gem_server"] = @host
    end

    @api_key = "EYKEY"

    keys = {
      :rubygems_api_key => "KEY",
      @host => @api_key,
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    send_battery
  end

  def test_sending_gem
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    send_battery
  end

  def test_sending_gem_to_allowed_push_host
    @host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = @host
    end

    @api_key = "PRIVKEY"

    keys = {
      :rubygems_api_key => "KEY",
      @host => @api_key,
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")
    send_battery
  end

  def test_sending_gem_with_env_var_api_key
    @host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = @host
    end

    @api_key = "PRIVKEY"
    ENV["GEM_HOST_API_KEY"] = "PRIVKEY"

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")
    send_battery
  end

  def test_sending_gem_to_allowed_push_host_with_basic_credentials
    @sanitized_host = "http://privategemserver.example"
    @host           = "http://user:password@privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = @sanitized_host
    end

    @api_key = "DOESNTMATTER"

    keys = {
      rubygems_api_key: @api_key,
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")
    send_battery
  end

  def test_sending_gem_to_disallowed_default_host
    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = "https://privategemserver.example"
    end

    response = %(ERROR:  "#{@host}" is not allowed by the gemspec, which only allows "https://privategemserver.example")

    assert_raise Gem::MockGemUi::TermError do
      send_battery
    end

    assert_match response, @ui.error
  end

  def test_sending_gem_to_disallowed_push_host
    @host = "https://anotherprivategemserver.example"
    push_host = "https://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata["allowed_push_host"] = push_host
    end

    @api_key = "PRIVKEY"

    keys = {
      :rubygems_api_key => "KEY",
      @host => @api_key,
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    response = "ERROR:  \"#{@host}\" is not allowed by the gemspec, which only allows \"#{push_host}\""

    assert_raise Gem::MockGemUi::TermError do
      send_battery
    end

    assert_match response, @ui.error
  end

  def test_sending_gem_defaulting_to_allowed_push_host
    host = "http://privategemserver.example"

    @spec, @path = util_gem "freebird", "1.0.1" do |spec|
      spec.metadata.delete("default_gem_server")
      spec.metadata["allowed_push_host"] = host
    end

    api_key = "PRIVKEY"

    keys = {
      host => api_key,
    }

    File.open Gem.configuration.credentials_path, "w" do |f|
      f.write Gem::ConfigFile.dump_with_rubygems_yaml(keys)
    end
    Gem.configuration.load_api_keys

    FileUtils.rm Gem.configuration.credentials_path

    @response = "Successfully registered gem: freebird (1.0.1)"
    @fetcher.data["#{host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")

    # do not set @host
    use_ui(@ui) { @cmd.send_gem(@path) }

    assert_match(/Pushing gem to #{host}.../, @ui.output)

    assert_equal Gem::Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal File.size(@path), @fetcher.last_request["Content-Length"].to_i
    assert_equal "application/octet-stream", @fetcher.last_request["Content-Type"]
    assert_equal api_key, @fetcher.last_request["Authorization"]

    assert_match @response, @ui.output
  end

  def test_sending_gem_to_host_permanent_redirect
    @host = "http://rubygems.example"
    redirected_uri = "https://rubygems.example/api/v1/gems"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(
      body: "",
      code: 308,
      msg: "Permanent Redirect",
      headers: { "Location" => redirected_uri }
    )

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.instance_variable_set :@host, @host
        @cmd.send_gem(@path)
      end
    end

    response = "The request has redirected permanently to #{redirected_uri}. Please check your defined push host URL."
    assert_match response, @ui.output
  end

  def test_raises_error_with_no_arguments
    def @cmd.sign_in(*); end
    assert_raise Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_sending_gem_denied
    response = "You don't have permission to push to this gem"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: response, code: 403, msg: "Forbidden")
    @cmd.instance_variable_set :@host, @host

    assert_raise Gem::MockGemUi::TermError do
      use_ui @ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @ui.output
  end

  def test_sending_gem_key
    @response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["#{@host}/api/v1/gems"] = HTTPResponseFactory.create(body: @response, code: 200, msg: "OK")
    File.open Gem.configuration.credentials_path, "a" do |f|
      f.write ":other: 701229f217cdf23b1344c7b4b54ca97"
    end
    Gem.configuration.load_api_keys

    @cmd.handle_options %w[-k other]
    @cmd.instance_variable_set :@host, @host
    @cmd.send_gem(@path)

    assert_equal Gem.configuration.api_keys[:other],
                 @fetcher.last_request["Authorization"]
  end

  def test_otp_verified_success
    response_success = "Successfully registered gem: freewill (1.0.0)"

    @fetcher.respond_with_require_otp("#{Gem.host}/api/v1/gems", response_success)

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.send_gem(@path)
    end

    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @otp_ui.output
    assert_match "Code: ", @otp_ui.output
    assert_match response_success, @otp_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_otp_verified_failure
    response = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    @fetcher.data["#{Gem.host}/api/v1/gems"] = HTTPResponseFactory.create(body: response, code: 401, msg: "Unauthorized")
    @fetcher.data["#{Gem.host}/api/v1/webauthn_verification"] =
      HTTPResponseFactory.create(body: "You don't have any security devices", code: 422, msg: "Unprocessable Entity")

    @otp_ui = Gem::MockGemUi.new "111111\n"
    assert_raise Gem::MockGemUi::TermError do
      use_ui @otp_ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @otp_ui.output
    assert_match "You have enabled multi-factor authentication. Please enter OTP code.", @otp_ui.output
    assert_match "Code: ", @otp_ui.output
    assert_equal "111111", @fetcher.last_request["OTP"]
  end

  def test_with_webauthn_enabled_success
    response_success = "Successfully registered gem: freewill (1.0.0)"
    server = Gem::MockTCPServer.new

    @fetcher.respond_with_require_otp("#{Gem.host}/api/v1/gems", response_success)
    @fetcher.respond_with_webauthn_url

    TCPServer.stub(:new, server) do
      Gem::GemcutterUtilities::WebauthnListener.stub(:listener_thread, Thread.new { Thread.current[:otp] = "Uvh6T57tkWuUnWYo" }) do
        use_ui @ui do
          @cmd.send_gem(@path)
        end
      end
    end

    assert_match "You have enabled multi-factor authentication. Please visit the following URL " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match @fetcher.webauthn_url_with_port(server.port), @ui.output
    assert_match "You are verified with a security device. You may close the browser window.", @ui.output
    assert_equal "Uvh6T57tkWuUnWYo", @fetcher.last_request["OTP"]
    assert_match response_success, @ui.output
  end

  def test_with_webauthn_enabled_failure
    pend "Flaky on TruffleRuby" if RUBY_ENGINE == "truffleruby"
    response_success = "Successfully registered gem: freewill (1.0.0)"
    server = Gem::MockTCPServer.new
    error = Gem::WebauthnVerificationError.new("Something went wrong")

    @fetcher.respond_with_require_otp("#{Gem.host}/api/v1/gems", response_success)
    @fetcher.respond_with_webauthn_url

    error = assert_raise Gem::MockGemUi::TermError do
      TCPServer.stub(:new, server) do
        Gem::GemcutterUtilities::WebauthnListener.stub(:listener_thread, Thread.new { Thread.current[:error] = error }) do
          use_ui @ui do
            @cmd.send_gem(@path)
          end
        end
      end
    end
    assert_equal 1, error.exit_code

    assert_match @fetcher.last_request["Authorization"], Gem.configuration.rubygems_api_key
    assert_match "You have enabled multi-factor authentication. Please visit the following URL " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match @fetcher.webauthn_url_with_port(server.port), @ui.output
    assert_match "ERROR:  Security device verification failed: Something went wrong", @ui.error
    refute_match "You are verified with a security device. You may close the browser window.", @ui.output
    refute_match response_success, @ui.output
  end

  def test_with_webauthn_enabled_success_with_polling
    response_success = "Successfully registered gem: freewill (1.0.0)"
    server = Gem::MockTCPServer.new

    @fetcher.respond_with_require_otp("#{Gem.host}/api/v1/gems", response_success)
    @fetcher.respond_with_webauthn_url
    @fetcher.respond_with_webauthn_polling("Uvh6T57tkWuUnWYo")

    TCPServer.stub(:new, server) do
      use_ui @ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match "You have enabled multi-factor authentication. Please visit the following URL " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match @fetcher.webauthn_url_with_port(server.port), @ui.output
    assert_match "You are verified with a security device. You may close the browser window.", @ui.output
    assert_equal "Uvh6T57tkWuUnWYo", @fetcher.last_request["OTP"]
    assert_match response_success, @ui.output
  end

  def test_with_webauthn_enabled_failure_with_polling
    response_success = "Successfully registered gem: freewill (1.0.0)"
    server = Gem::MockTCPServer.new

    @fetcher.respond_with_require_otp("#{Gem.host}/api/v1/gems", response_success)
    @fetcher.respond_with_webauthn_url
    @fetcher.respond_with_webauthn_polling_failure

    error = assert_raise Gem::MockGemUi::TermError do
      TCPServer.stub(:new, server) do
        use_ui @ui do
          @cmd.send_gem(@path)
        end
      end
    end
    assert_equal 1, error.exit_code

    assert_match @fetcher.last_request["Authorization"], Gem.configuration.rubygems_api_key
    assert_match "You have enabled multi-factor authentication. Please visit the following URL " \
      "to authenticate via security device. If you can't verify using WebAuthn but have OTP enabled, " \
      "you can re-run the gem signin command with the `--otp [your_code]` option.", @ui.output
    assert_match @fetcher.webauthn_url_with_port(server.port), @ui.output
    assert_match "ERROR:  Security device verification failed: The token in the link you used has either expired " \
      "or been used already.", @ui.error
    refute_match "You are verified with a security device. You may close the browser window.", @ui.output
    refute_match response_success, @ui.output
  end

  def test_sending_gem_unauthorized_api_key_with_mfa_enabled
    response_mfa_enabled = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    response_forbidden = "The API key doesn't have access"
    response_success   = "Successfully registered gem: freewill (1.0.0)"

    @fetcher.data["#{@host}/api/v1/gems"] = [
      HTTPResponseFactory.create(body: response_mfa_enabled, code: 401, msg: "Unauthorized"),
      HTTPResponseFactory.create(body: response_forbidden, code: 403, msg: "Forbidden"),
      HTTPResponseFactory.create(body: response_success, code: 200, msg: "OK"),
    ]
    @fetcher.data["#{@host}/api/v1/webauthn_verification"] =
      HTTPResponseFactory.create(body: "You don't have any security devices", code: 422, msg: "Unprocessable Entity")

    @fetcher.data["#{@host}/api/v1/api_key"] = HTTPResponseFactory.create(body: "", code: 200, msg: "OK")
    @cmd.instance_variable_set :@host, @host
    @cmd.instance_variable_set :@scope, :push_rubygem

    @ui = Gem::MockGemUi.new "11111\nsome@mail.com\npass\n"
    use_ui @ui do
      @cmd.send_gem(@path)
    end

    mfa_notice = "You have enabled multi-factor authentication. Please enter OTP code."
    access_notice = "The existing key doesn't have access of push_rubygem on https://rubygems.example. Please sign in to update access."
    assert_match mfa_notice, @ui.output
    assert_match access_notice, @ui.output
    assert_match "Username/email:", @ui.output
    assert_match "Password:", @ui.output
    assert_match "Added push_rubygem scope to the existing API key", @ui.output
    assert_match response_success, @ui.output
    assert_equal "11111", @fetcher.last_request["OTP"]
  end

  def test_sending_gem_with_no_local_creds
    Gem.configuration.rubygems_api_key = nil

    response_mfa_enabled = "You have enabled multifactor authentication but your request doesn't have the correct OTP code. Please check it and retry."
    response_success     = "Successfully registered gem: freewill (1.0.0)"
    response_profile     = "mfa: disabled\n"

    @fetcher.data["#{@host}/api/v1/gems"] = [
      HTTPResponseFactory.create(body: response_success, code: 200, msg: "OK"),
    ]

    @fetcher.data["#{@host}/api/v1/api_key"] = [
      HTTPResponseFactory.create(body: response_mfa_enabled, code: 401, msg: "Unauthorized"),
      HTTPResponseFactory.create(body: "", code: 200, msg: "OK"),
    ]

    @fetcher.data["#{@host}/api/v1/profile/me.yaml"] = [
      HTTPResponseFactory.create(body: response_profile, code: 200, msg: "OK"),
    ]
    @fetcher.data["#{@host}/api/v1/webauthn_verification"] =
      HTTPResponseFactory.create(body: "You don't have any security devices", code: 422, msg: "Unprocessable Entity")

    @cmd.instance_variable_set :@scope, :push_rubygem
    @cmd.options[:args] = [@path]
    @cmd.options[:host] = @host

    @ui = Gem::MockGemUi.new "some@mail.com\npass\n11111\n"
    use_ui @ui do
      @cmd.execute
    end

    mfa_notice = "You have enabled multi-factor authentication. Please enter OTP code."
    assert_match mfa_notice, @ui.output
    assert_match "Enter your https://rubygems.example credentials.", @ui.output
    assert_match "Username/email:", @ui.output
    assert_match "Password:", @ui.output
    assert_match "Signed in with API key:", @ui.output
    assert_match response_success, @ui.output
    assert_equal "11111", @fetcher.last_request["OTP"]
  end

  private

  def assert_attestation_multipart(attestation_payload)
    assert_equal "multipart", @fetcher.last_request.main_type, @fetcher.last_request.content_type
    assert_equal "form-data", @fetcher.last_request.sub_type
    assert_include @fetcher.last_request.type_params, "boundary"
    boundary = @fetcher.last_request.type_params["boundary"]

    parts = @fetcher.last_request.body.split(/(?:\r\n|\A)--#{Regexp.quote(boundary)}(?:\r\n|--)/m)
    refute_empty parts
    assert_empty parts[0]
    parts.shift # remove the first empty part

    p1 = parts.shift
    p2 = parts.shift
    assert_equal "\r\n", parts.shift
    assert_empty parts

    assert_equal [
      "Content-Disposition: form-data; name=\"gem\"; filename=\"#{@path}\"",
      "Content-Type: application/octet-stream",
      nil,
      Gem.read_binary(@path),
    ].join("\r\n").b, p1
    assert_equal [
      "Content-Disposition: form-data; name=\"attestations\"",
      nil,
      "[#{attestation_payload}]",
    ].join("\r\n").b, p2
  end

  def singleton_gem_class
    class << Gem; self; end
  end
end
