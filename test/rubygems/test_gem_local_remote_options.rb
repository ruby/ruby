require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/local_remote_options'
require 'rubygems/command'

class TestGemLocalRemoteOptions < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Command.new 'dummy', 'dummy'
    @cmd.extend Gem::LocalRemoteOptions
  end

  def test_add_local_remote_options
    @cmd.add_local_remote_options

    args = %w[-l -r -b -B 10 --source http://gems.example.com -p --update-sources]
    assert @cmd.handles?(args)
  end

  def test_local_eh
    assert_equal false, @cmd.local?

    @cmd.options[:domain] = :local

    assert_equal true, @cmd.local?

    @cmd.options[:domain] = :both

    assert_equal true, @cmd.local?
  end

  def test_remote_eh
    assert_equal false, @cmd.remote?

    @cmd.options[:domain] = :remote

    assert_equal true, @cmd.remote?

    @cmd.options[:domain] = :both

    assert_equal true, @cmd.remote?
  end

  def test_source_option
    @cmd.add_source_option

    s1 = URI.parse 'http://more-gems.example.com'
    s2 = URI.parse 'http://even-more-gems.example.com'

    @cmd.handle_options %W[--source #{s1} --source #{s2}]

    assert_equal [s1, s2], Gem.sources
  end

  def test_update_sources_option
    @cmd.add_update_sources_option

    Gem.configuration.update_sources = false

    @cmd.handle_options %W[--update-sources]

    assert_equal true, Gem.configuration.update_sources

    @cmd.handle_options %W[--no-update-sources]

    assert_equal false, Gem.configuration.update_sources
  end

  def test_source_option_bad
    @cmd.add_source_option

    s1 = 'htp://more-gems.example.com'

    assert_raise OptionParser::InvalidArgument do
      @cmd.handle_options %W[--source #{s1}]
    end

    assert_equal %w[http://gems.example.com], Gem.sources
  end

end

