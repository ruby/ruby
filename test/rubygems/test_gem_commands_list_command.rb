######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/commands/list_command'

class TestGemCommandsListCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::ListCommand.new

    util_setup_fake_fetcher

    @si = util_setup_spec_fetcher @a1, @a2, @pl1

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end
  end

  def test_execute_installed
    @cmd.handle_options %w[c --installed]

    e = assert_raises Gem::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal 0, e.exit_code

    assert_equal "true\n", @ui.output

    assert_equal '', @ui.error
  end

end
