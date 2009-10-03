require 'test/unit'
require 'rake'
require 'rake/loaders/makefile'

class Rake::TestMakefileLoader < Test::Unit::TestCase
  include Rake

  def test_parse
    Task.clear
    loader = Rake::MakefileLoader.new
    loader.load("#{File.dirname(__FILE__)}/data/sample.mf")
    %w(a b c d).each do |t|
      assert Task.task_defined?(t), "#{t} should be a defined task"
    end
    assert_equal %w(a1 a2 a3 a4 a5 a6 a7).sort, Task['a'].prerequisites.sort
    assert_equal %w(b1 b2 b3 b4 b5 b6 b7).sort, Task['b'].prerequisites.sort
    assert_equal %w(c1).sort, Task['c'].prerequisites.sort
    assert_equal %w(d1 d2).sort, Task['d'].prerequisites.sort
    assert_equal %w(e1 f1).sort, Task['e'].prerequisites.sort
    assert_equal %w(e1 f1).sort, Task['f'].prerequisites.sort
    assert_equal ["g1", "g 2", "g 3", "g4"].sort, Task['g 0'].prerequisites.sort
    assert_equal 7, Task.tasks.size
  end
end
