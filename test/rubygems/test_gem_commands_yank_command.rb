# frozen_string_literal: false
require 'rubygems/test_case'
require 'rubygems/commands/yank_command'

class TestGemCommandsYankCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::YankCommand.new
    @cmd.host = 'http://example'

    @fetcher = Gem::RemoteFetcher.fetcher

    Gem.configuration.rubygems_api_key = 'key'
    Gem.configuration.api_keys[:KEY]  = 'other'
  end

  def test_handle_options
    @cmd.handle_options %w[a --version 1.0 --platform x86-darwin -k KEY]

    assert_equal %w[a],        @cmd.options[:args]
    assert_equal :KEY,         @cmd.options[:key]
    assert_nil                 @cmd.options[:platform]
    assert_equal req('= 1.0'), @cmd.options[:version]
  end

  def test_handle_options_missing_argument
    %w[-v --version -p --platform].each do |option|
      assert_raises OptionParser::MissingArgument do
        @cmd.handle_options %W[a #{option}]
      end
    end
  end

  def test_execute
    yank_uri = 'http://example/api/v1/gems/yank'
    @fetcher.data[yank_uri] = ['Successfully yanked', 200, 'OK']

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req('= 1.0')

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%Yanking gem from http://example%, @ui.output
    assert_match %r%Successfully yanked%,      @ui.output

    platform = Gem.platforms[1]
    body = @fetcher.last_request.body.split('&').sort
    assert_equal %W[gem_name=a platform=#{platform} version=1.0], body

    assert_equal 'key', @fetcher.last_request['Authorization']

    assert_equal [yank_uri], @fetcher.paths
  end

  def test_execute_key
    yank_uri = 'http://example/api/v1/gems/yank'
    @fetcher.data[yank_uri] = ['Successfully yanked', 200, 'OK']

    @cmd.options[:args]    = %w[a]
    @cmd.options[:version] = req('= 1.0')
    @cmd.options[:key]     = :KEY

    use_ui @ui do
      @cmd.execute
    end

    body = @fetcher.last_request.body.split('&').sort
    assert_equal %w[gem_name=a version=1.0], body
    assert_equal 'other', @fetcher.last_request['Authorization']
  end

  def test_execute_undo
    unyank_uri = 'http://example/api/v1/gems/unyank'
    @fetcher.data[unyank_uri] = ['Successfully unyanked', 200, 'OK']

    @cmd.options[:args]    = %w[a]
    @cmd.options[:version] = req('= 1.0')
    @cmd.options[:undo]    = true

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%Unyanking gem from http://example%, @ui.output
    assert_match %r%Successfully unyanked%,      @ui.output

    body = @fetcher.last_request.body.split('&').sort
    assert_equal %w[gem_name=a version=1.0], body

    assert_equal [unyank_uri], @fetcher.paths
  end

end

