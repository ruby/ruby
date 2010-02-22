require_relative 'gemutilities'
require 'rubygems/commands/push_command'

class TestGemCommandsPushCommand < RubyGemTestCase

  def setup
    super

    @gems_dir = File.join @tempdir, 'gems'
    @cache_dir = File.join @gemhome, 'cache'
    FileUtils.mkdir @gems_dir
    Gem.configuration.rubygems_api_key = "ed244fbf2b1a52e012da8616c512fa47f9aa5250"
    @spec, @path = util_gem("freewill", "1.0.0")

    @fetcher = Gem::FakeFetcher.new
    Gem::RemoteFetcher.fetcher = @fetcher

    @cmd = Gem::Commands::PushCommand.new
  end

  def test_sending_gem
    response = "Successfully registered gem: freewill (1.0.0)"
    @fetcher.data["https://rubygems.org/api/v1/gems"] = [response, 200, 'OK']

    use_ui @ui do
      @cmd.send_gem(@path)
    end

    assert_match %r{Pushing gem to RubyGems.org...}, @ui.output

    assert_equal Net::HTTP::Post, @fetcher.last_request.class
    assert_equal Gem.read_binary(@path), @fetcher.last_request.body
    assert_equal File.size(@path), @fetcher.last_request["Content-Length"].to_i
    assert_equal "application/octet-stream", @fetcher.last_request["Content-Type"]
    assert_equal Gem.configuration.rubygems_api_key, @fetcher.last_request["Authorization"]

    assert_match response, @ui.output
  end

  def test_raises_error_with_no_arguments
    def @cmd.sign_in; end
    assert_raises Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_sending_gem_denied
    response = "You don't have permission to push to this gem"
    @fetcher.data["https://rubygems.org/api/v1/gems"] = [response, 403, 'Forbidden']

    assert_raises MockGemUi::TermError do
      use_ui @ui do
        @cmd.send_gem(@path)
      end
    end

    assert_match response, @ui.output
  end

end

