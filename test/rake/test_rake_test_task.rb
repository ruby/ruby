require File.expand_path('../helper', __FILE__)
require 'rake/testtask'

class TestRakeTestTask < Rake::TestCase
  include Rake

  def setup
    super

    Task.clear
    ENV.delete('TEST')
  end

  def test_no_task
    assert ! Task.task_defined?(:test)
  end

  def test_defaults
    tt = Rake::TestTask.new do |t| end
    refute_nil tt
    assert_equal :test, tt.name
    assert_equal ['lib'], tt.libs
    assert_equal 'test/test*.rb', tt.pattern
    assert_equal false, tt.verbose
    assert Task.task_defined?(:test)
  end

  def test_non_defaults
    tt = Rake::TestTask.new(:example) do |t|
      t.libs = ['src', 'ext']
      t.pattern = 'test/tc_*.rb'
      t.verbose = true
    end
    refute_nil tt
    assert_equal :example, tt.name
    assert_equal ['src', 'ext'], tt.libs
    assert_equal 'test/tc_*.rb', tt.pattern
    assert_equal true, tt.verbose
    assert Task.task_defined?(:example)
  end

  def test_pattern
    tt = Rake::TestTask.new do |t|
      t.pattern = '*.rb'
    end
    assert_equal ['*.rb'], tt.file_list.to_a
  end

  def test_env_test
    ENV['TEST'] = 'testfile.rb'
    tt = Rake::TestTask.new do |t|
      t.pattern = '*'
    end
    assert_equal ["testfile.rb"], tt.file_list.to_a
  end

  def test_test_files
    tt = Rake::TestTask.new do |t|
      t.test_files = FileList['a.rb', 'b.rb']
    end
    assert_equal ["a.rb", 'b.rb'], tt.file_list.to_a
  end

  def test_both_pattern_and_test_files
    tt = Rake::TestTask.new do |t|
      t.test_files = FileList['a.rb', 'b.rb']
      t.pattern = '*.rb'
    end
    assert_equal ['a.rb', 'b.rb', '*.rb'], tt.file_list.to_a
  end

  def test_direct_run_has_quoted_paths
    test_task = Rake::TestTask.new(:tx) do |t|
      t.loader = :direct
    end
    assert_match(/-e ".*"/, test_task.run_code)
  end

  def test_testrb_run_has_quoted_paths_on_ruby_182
    test_task = Rake::TestTask.new(:tx) do |t|
      t.loader = :testrb
    end
    flexmock(test_task).should_receive(:ruby_version).and_return('1.8.2')
    assert_match(/^-S testrb +".*"$/, test_task.run_code)
  end

  def test_testrb_run_has_quoted_paths_on_ruby_186
    test_task = Rake::TestTask.new(:tx) do |t|
      t.loader = :testrb
    end
    flexmock(test_task).should_receive(:ruby_version).and_return('1.8.6')
    assert_match(/^-S testrb +$/, test_task.run_code)
  end

  def test_rake_run_has_quoted_paths
    test_task = Rake::TestTask.new(:tx) do |t|
      t.loader = :rake
    end
    assert_match(/".*"/, test_task.run_code)
  end

  def test_nested_libs_will_be_flattened
    test_task = Rake::TestTask.new(:tx) do |t|
      t.libs << ["A", "B"]
    end
    sep = File::PATH_SEPARATOR
    assert_match(/lib#{sep}A#{sep}B/, test_task.ruby_opts_string)
  end

  def test_empty_lib_path_implies_no_dash_I_option
    test_task = Rake::TestTask.new(:tx) do |t|
      t.libs = []
    end
    refute_match(/-I/, test_task.ruby_opts_string)
  end
end
