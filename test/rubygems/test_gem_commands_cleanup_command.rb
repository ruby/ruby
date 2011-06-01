######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems/commands/cleanup_command'

class TestGemCommandsCleanupCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::CleanupCommand.new

    @a_1 = quick_spec 'a', 1
    @a_2 = quick_spec 'a', 2

    install_gem @a_1
    install_gem @a_2
  end

  def test_execute
    @cmd.options[:args] = %w[a]

    @cmd.execute

    refute_path_exists @a_1.gem_dir
  end

  def test_execute_all
    @b_1 = quick_spec 'b', 1
    @b_2 = quick_spec 'b', 2

    install_gem @b_1
    install_gem @b_2

    @cmd.options[:args] = []

    @cmd.execute

    refute_path_exists @a_1.gem_dir
    refute_path_exists @b_1.gem_dir
  end

  def test_execute_dry_run
    @cmd.options[:args] = %w[a]
    @cmd.options[:dryrun] = true

    @cmd.execute

    assert_path_exists @a_1.gem_dir
  end

end

