# frozen_string_literal: true
require_relative 'helper'
begin
  require 'rake'
rescue LoadError
end

class TestRDocTask < RDoc::TestCase

  def setup
    super

    Rake::Task.clear

    @t = RDoc::Task.new
  end

  def test_clobber_task_description
    assert_equal 'Remove RDoc HTML files', @t.clobber_task_description
  end

  def test_inline_source
    _, err = verbose_capture_output do
      assert @t.inline_source
    end

    assert_equal "RDoc::Task#inline_source is deprecated\n", err

    _, err = verbose_capture_output do
      @t.inline_source = false
    end

    assert_equal "RDoc::Task#inline_source is deprecated\n", err

    capture_output do
      assert @t.inline_source
    end
  end

  def test_markup_option
    rdoc_task = RDoc::Task.new do |rd|
      rd.markup = "tomdoc"
    end

    assert_equal %w[-o html --markup tomdoc], rdoc_task.option_list
  end

  def test_tasks_creation
    RDoc::Task.new
    assert Rake::Task[:rdoc]
    assert Rake::Task[:clobber_rdoc]
    assert Rake::Task[:rerdoc]
    assert_equal ["html/created.rid"], Rake::Task[:rdoc].prerequisites
  end

  def test_tasks_creation_with_custom_name_symbol
    rd = RDoc::Task.new(:rdoc_dev)
    assert Rake::Task[:rdoc_dev]
    assert Rake::Task[:clobber_rdoc_dev]
    assert Rake::Task[:rerdoc_dev]
    assert_equal :rdoc_dev, rd.name
  end

  def test_tasks_option_parser
    rdoc_task = RDoc::Task.new do |rd|
      rd.title = "Test Tasks Option Parser"
      rd.main = "README.md"
      rd.rdoc_files.include("README.md")
      rd.options << "--all"
    end

    assert rdoc_task.title, "Test Tasks Option Parser"
    assert rdoc_task.main, "README.md"
    assert rdoc_task.rdoc_files.include?("README.md")
    assert rdoc_task.options.include?("--all")

    args = %w[--all -o html --main README.md] << "--title" << "Test Tasks Option Parser" << "README.md"
    assert_equal args, rdoc_task.option_list + rdoc_task.rdoc_files
  end

  def test_generator_option
    rdoc_task = RDoc::Task.new do |rd|
      rd.generator = "ri"
    end

    assert_equal %w[-o html -f ri], rdoc_task.option_list
  end

  def test_main_option
    rdoc_task = RDoc::Task.new do |rd|
      rd.main = "README.md"
    end

    assert_equal %w[-o html --main README.md], rdoc_task.option_list
  end

  def test_output_dir_option
    rdoc_task = RDoc::Task.new do |rd|
      rd.rdoc_dir = "zomg"
    end

    assert_equal %w[-o zomg], rdoc_task.option_list
  end

  def test_rdoc_task_description
    assert_equal 'Build RDoc HTML files', @t.rdoc_task_description
  end

  def test_rerdoc_task_description
    assert_equal 'Rebuild RDoc HTML files', @t.rerdoc_task_description
  end

  def test_tasks_creation_with_custom_name_string
    rd = RDoc::Task.new("rdoc_dev")
    assert Rake::Task[:rdoc_dev]
    assert Rake::Task[:clobber_rdoc_dev]
    assert Rake::Task[:rerdoc_dev]
    assert_equal "rdoc_dev", rd.name
  end

  def test_tasks_creation_with_custom_name_hash
    options = {
      :rdoc => "rdoc",
      :clobber_rdoc => "rdoc:clean",
      :rerdoc => "rdoc:force"
    }

    Rake::Task.clear

    rd = RDoc::Task.new(options)
    assert Rake::Task[:"rdoc"]
    assert Rake::Task[:"rdoc:clean"]
    assert Rake::Task[:"rdoc:force"]
    assert_raise(RuntimeError) { Rake::Task[:clobber_rdoc] }
    assert_equal options, rd.name
  end

  def test_tasks_creation_with_custom_name_hash_will_use_default_if_an_option_isnt_given
    RDoc::Task.new(:clobber_rdoc => "rdoc:clean")
    assert Rake::Task[:rdoc]
    assert Rake::Task[:"rdoc:clean"]
    assert Rake::Task[:rerdoc]
  end

  def test_tasks_creation_with_custom_name_hash_raises_exception_if_invalid_option_given
    assert_raise(ArgumentError) do
      RDoc::Task.new(:foo => "bar")
    end

    begin
      RDoc::Task.new(:foo => "bar")
    rescue ArgumentError => e
      assert_match(/foo/, e.message)
    end
  end

  def test_template_option
    rdoc_task = RDoc::Task.new do |rd|
      rd.template = "foo"
    end

    assert_equal %w[-o html -T foo], rdoc_task.option_list
  end

  def test_title_option
    rdoc_task = RDoc::Task.new do |rd|
      rd.title = "Test Title Option"
    end

    assert_equal %w[-o html] << "--title" << "Test Title Option", rdoc_task.option_list
  end

end if defined?(Rake::Task)

