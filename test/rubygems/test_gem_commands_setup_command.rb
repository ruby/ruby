require 'rubygems/test_case'
require 'rubygems/commands/setup_command'

class TestGemCommandsSetupCommand < Gem::TestCase

  def setup
    super

    @install_dir = File.join @tempdir, 'install'
    @cmd = Gem::Commands::SetupCommand.new
    @cmd.options[:prefix] = @install_dir

    FileUtils.mkdir_p 'bin'
    FileUtils.mkdir_p 'lib/rubygems'

    open 'bin/gem',                   'w' do |io| io.puts '# gem'          end
    open 'lib/rubygems.rb',           'w' do |io| io.puts '# rubygems.rb'  end
    open 'lib/rubygems/test_case.rb', 'w' do |io| io.puts '# test_case.rb' end
  end

  def test_rb_files_in
    assert_equal %w[rubygems.rb rubygems/test_case.rb],
                 @cmd.rb_files_in('lib').sort
  end

  def test_remove_old_lib_files
    lib            = File.join @install_dir, 'lib'
    lib_rubygems   = File.join lib, 'rubygems'

    old_builder_rb = File.join lib_rubygems, 'builder.rb'
    old_format_rb  = File.join lib_rubygems, 'format.rb'

    FileUtils.mkdir_p lib_rubygems

    open old_builder_rb, 'w' do |io| io.puts '# builder.rb' end
    open old_format_rb,  'w' do |io| io.puts '# format.rb'  end

    @cmd.remove_old_lib_files lib

    refute_path_exists old_builder_rb
    refute_path_exists old_format_rb
  end

end

