# frozen_string_literal: true
require 'rubygems/test_case'
begin
  gem_home_files = lambda{
    if Dir.exist?(ENV["GEM_HOME"])
      require "find"
      ary = Find.find(ENV["GEM_HOME"]).to_a
    else
      []
    end
  }
  prev_gem_home = ENV["GEM_HOME"]
  prev_gem_home_files = gem_home_files.call
  prev_threads = Thread.list.map{|e| e.inspect}

  require 'rubygems/gem_runner'
ensure
  if $!
    msg = <<eom
***************
PREV
  GEM_HOME: #{prev_gem_home}
  Files in GEM_HOME: #{prev_gem_home_files.inspect}
  Threads: #{prev_threads.inspect}
Current:
  GEM_HOME: #{ENV["GEM_HOME"]}
  Files in GEM_HOME: #{gem_home_files.call}
  Threads: #{Thread.list.map{|e| e.inspect}.inspect}
Exception: #{$!.message}
eom
    p $!.class
    p $!.message.frozen?
    raise $!.class, msg, $!.backtrace
  end
end

class TestGemGemRunner < Gem::TestCase

  def setup
    super

    @orig_args = Gem::Command.build_args
    @runner = Gem::GemRunner.new
  end

  def teardown
    super

    Gem::Command.build_args = @orig_args
  end

  def test_do_configuration
    Gem.clear_paths

    temp_conf = File.join @tempdir, '.gemrc'

    other_gem_path = File.join @tempdir, 'other_gem_path'
    other_gem_home = File.join @tempdir, 'other_gem_home'

    Gem.ensure_gem_subdirectories other_gem_path
    Gem.ensure_gem_subdirectories other_gem_home

    File.open temp_conf, 'w' do |fp|
      fp.puts "gem: --commands"
      fp.puts "gemhome: #{other_gem_home}"
      fp.puts "gempath:"
      fp.puts "  - #{other_gem_path}"
      fp.puts "rdoc: --all"
    end

    gr = Gem::GemRunner.new
    gr.send :do_configuration, %W[--config-file #{temp_conf}]

    assert_equal [other_gem_path, other_gem_home], Gem.path
    assert_equal %w[--commands], Gem::Command.extra_args
  end

  def test_extract_build_args
    args = %w[]
    assert_equal [], @runner.extract_build_args(args)
    assert_equal %w[], args

    args = %w[foo]
    assert_equal [], @runner.extract_build_args(args)
    assert_equal %w[foo], args

    args = %w[--foo]
    assert_equal [], @runner.extract_build_args(args)
    assert_equal %w[--foo], args

    args = %w[--foo --]
    assert_equal [], @runner.extract_build_args(args)
    assert_equal %w[--foo], args

    args = %w[--foo -- --bar]
    assert_equal %w[--bar], @runner.extract_build_args(args)
    assert_equal %w[--foo], args
  end

end

