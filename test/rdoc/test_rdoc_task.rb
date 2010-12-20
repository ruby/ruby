require 'rubygems'
require 'minitest/autorun'
require 'rdoc/task'

class TestRDocTask < MiniTest::Unit::TestCase

  def setup
    Rake::Task.clear
  end

  def test_tasks_creation
    RDoc::Task.new
    assert Rake::Task[:rdoc]
    assert Rake::Task[:clobber_rdoc]
    assert Rake::Task[:rerdoc]
  end

  def test_tasks_creation_with_custom_name_symbol
    rd = RDoc::Task.new(:rdoc_dev)
    assert Rake::Task[:rdoc_dev]
    assert Rake::Task[:clobber_rdoc_dev]
    assert Rake::Task[:rerdoc_dev]
    assert_equal :rdoc_dev, rd.name
  end

  def test_tasks_creation_with_custom_name_string
    rd = RDoc::Task.new("rdoc_dev")
    assert Rake::Task[:rdoc_dev]
    assert Rake::Task[:clobber_rdoc_dev]
    assert Rake::Task[:rerdoc_dev]
    assert_equal "rdoc_dev", rd.name
  end

  def test_tasks_creation_with_custom_name_hash
    options = { :rdoc => "rdoc", :clobber_rdoc => "rdoc:clean", :rerdoc => "rdoc:force" }
    rd = RDoc::Task.new(options)
    assert Rake::Task[:"rdoc"]
    assert Rake::Task[:"rdoc:clean"]
    assert Rake::Task[:"rdoc:force"]
    assert_raises(RuntimeError) { Rake::Task[:clobber_rdoc] }
    assert_equal options, rd.name
  end

  def test_tasks_creation_with_custom_name_hash_will_use_default_if_an_option_isnt_given
    RDoc::Task.new(:clobber_rdoc => "rdoc:clean")
    assert Rake::Task[:rdoc]
    assert Rake::Task[:"rdoc:clean"]
    assert Rake::Task[:rerdoc]
  end

  def test_tasks_creation_with_custom_name_hash_raises_exception_if_invalid_option_given
    assert_raises(ArgumentError) do
      RDoc::Task.new(:foo => "bar")
    end

    begin
      RDoc::Task.new(:foo => "bar")
    rescue ArgumentError => e
      assert_match(/foo/, e.message)
    end
  end

end

