require File.expand_path('../helper', __FILE__)

class TestRakeRakeTestLoader < Rake::TestCase

  def test_pattern
    orig_loaded_features = $:.dup
    FileUtils.touch 'foo.rb'
    FileUtils.touch 'test_a.rb'
    FileUtils.touch 'test_b.rb'

    ARGV.replace %w[foo.rb test_*.rb -v]

    load File.join(@rake_lib, 'rake/rake_test_loader.rb')

    assert_equal %w[-v], ARGV
  ensure
    $:.replace orig_loaded_features
  end

end
