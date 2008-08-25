require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/indexer'
require 'rubygems/commands/generate_index_command'

class TestGemCommandsGenerateIndexCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::GenerateIndexCommand.new
    @cmd.options[:directory] = @gemhome
  end

  def test_execute
    use_ui @ui do
      @cmd.execute
    end

    yaml = File.join @gemhome, 'yaml'
    yaml_z = File.join @gemhome, 'yaml.Z'
    quick_index = File.join @gemhome, 'quick', 'index'
    quick_index_rz = File.join @gemhome, 'quick', 'index.rz'

    assert File.exist?(yaml), yaml
    assert File.exist?(yaml_z), yaml_z
    assert File.exist?(quick_index), quick_index
    assert File.exist?(quick_index_rz), quick_index_rz
  end

end if ''.respond_to? :to_xs

