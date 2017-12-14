require 'rubygems/test_case'
require 'rubygems/commands/mirror_command'

class TestGemCommandsMirrorCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::MirrorCommand.new

    @mirror_specs = Gem::Specification.find_all_by_name('rubygems-mirror').each do |spec|
      Gem::Specification.remove_spec spec
    end
  end

  def teardown
    @mirror_specs.each do |spec|
      Gem::Specification.add_spec spec
    end

    super
  end

  def test_execute
    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%Install the rubygems-mirror%i, @ui.error
  end

end
