require 'test/unit'
require 'rake/rdoctask'

class Rake::TestRDocTask < Test::Unit::TestCase
  include Rake
  
  def setup
    Task.clear
  end
  
  def test_tasks_creation
    Rake::RDocTask.new
    assert Task[:rdoc]
    assert Task[:clobber_rdoc]
    assert Task[:rerdoc]
  end
  
  def test_tasks_creation_with_custom_name_symbol
    rd = Rake::RDocTask.new(:rdoc_dev)
    assert Task[:rdoc_dev]
    assert Task[:clobber_rdoc_dev]
    assert Task[:rerdoc_dev]
    assert_equal :rdoc_dev, rd.name
  end
  
  def test_tasks_creation_with_custom_name_string
    rd = Rake::RDocTask.new("rdoc_dev")
    assert Task[:rdoc_dev]
    assert Task[:clobber_rdoc_dev]
    assert Task[:rerdoc_dev]
    assert_equal "rdoc_dev", rd.name
  end
  
  def test_tasks_creation_with_custom_name_hash
    options = { :rdoc => "rdoc", :clobber_rdoc => "rdoc:clean", :rerdoc => "rdoc:force" }
    rd = Rake::RDocTask.new(options)
    assert Task[:"rdoc"]
    assert Task[:"rdoc:clean"]
    assert Task[:"rdoc:force"]
    assert_raises(RuntimeError) { Task[:clobber_rdoc] }
    assert_equal options, rd.name
  end
  
  def test_tasks_creation_with_custom_name_hash_will_use_default_if_an_option_isnt_given
    rd = Rake::RDocTask.new(:clobber_rdoc => "rdoc:clean")
    assert Task[:rdoc]
    assert Task[:"rdoc:clean"]
    assert Task[:rerdoc]
  end
  
  def test_tasks_creation_with_custom_name_hash_raises_exception_if_invalid_option_given
    assert_raises(ArgumentError) do
      Rake::RDocTask.new(:foo => "bar")
    end
    
    begin
      Rake::RDocTask.new(:foo => "bar")
    rescue ArgumentError => e
      assert_match(/foo/, e.message)
    end
  end
  
  def test_inline_source_is_enabled_by_default
    rd = Rake::RDocTask.new
    assert rd.option_list.include?('--inline-source')
  end
  
  def test_inline_source_option_is_only_appended_if_option_not_already_given
    rd = Rake::RDocTask.new
    rd.options << '--inline-source'
    assert_equal 1, rd.option_list.grep('--inline-source').size
    
    rd = Rake::RDocTask.new
    rd.options << '-S'
    assert_equal 1, rd.option_list.grep('-S').size
    assert_equal 0, rd.option_list.grep('--inline-source').size
  end
  
  def test_inline_source_option_can_be_disabled
    rd = Rake::RDocTask.new
    rd.inline_source = false
    assert !rd.option_list.include?('--inline-source')
  end
end
