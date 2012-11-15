require File.expand_path('../helper', __FILE__)
require 'open3'

class TestRakeReduceCompat < Rake::TestCase
  # TODO: factor out similar code in test_rake_functional.rb
  def rake(*args)
    lib = File.join(@orig_PWD, "lib")
    bin_rake = File.join(@orig_PWD, "bin", "rake")
    Open3.popen3(RUBY, "-I", lib, bin_rake, *args) { |_, out, _, _| out.read }
  end
  
  def invoke_normal(task_name)
    rake task_name.to_s
  end

  def invoke_reduce_compat(task_name)
    rake "--reduce-compat", task_name.to_s
  end

  def test_no_deprecated_dsl
    rakefile %q{
      task :check_task do
        Module.new { p defined?(task) }
      end

      task :check_file do
        Module.new { p defined?(file) }
      end
    }
    
    assert_equal %{"method"}, invoke_normal(:check_task).chomp
    assert_equal %{"method"}, invoke_normal(:check_file).chomp

    assert_equal "nil", invoke_reduce_compat(:check_task).chomp
    assert_equal "nil", invoke_reduce_compat(:check_file).chomp
  end

  def test_no_classic_namespace
    rakefile %q{
      task :check_task do
        begin
          Task
          print "present"
        rescue NameError
          print "absent"
        end
      end

      task :check_file_task do
        begin
          FileTask
          print "present"
        rescue NameError
          print "absent"
        end
      end
    }

    assert_equal "present", invoke_normal(:check_task)
    assert_equal "present", invoke_normal(:check_file_task)

    assert_equal "absent", invoke_reduce_compat(:check_task)
    assert_equal "absent", invoke_reduce_compat(:check_file_task)
  end
end
