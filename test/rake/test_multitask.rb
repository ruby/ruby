require 'test/unit'
require 'rake'

######################################################################
class Rake::TestMultiTask < Test::Unit::TestCase
  include Rake

  def setup
    Task.clear
    @runs = Array.new
  end

  def test_running_multitasks
    task :a do 3.times do |i| @runs << "A#{i}"; sleep 0.01; end end
    task :b do 3.times do |i| @runs << "B#{i}"; sleep 0.01;  end end
    multitask :both => [:a, :b]
    Task[:both].invoke
    assert_equal 6, @runs.size
    assert @runs.index("A0") < @runs.index("A1")
    assert @runs.index("A1") < @runs.index("A2")
    assert @runs.index("B0") < @runs.index("B1")
    assert @runs.index("B1") < @runs.index("B2")
  end

  def test_all_multitasks_wait_on_slow_prerequisites
    task :slow do 3.times do |i| @runs << "S#{i}"; sleep 0.05 end end
    task :a => [:slow] do 3.times do |i| @runs << "A#{i}"; sleep 0.01 end end
    task :b => [:slow] do 3.times do |i| @runs << "B#{i}"; sleep 0.01 end end
    multitask :both => [:a, :b]
    Task[:both].invoke
    assert_equal 9, @runs.size
    assert @runs.index("S0") < @runs.index("S1")
    assert @runs.index("S1") < @runs.index("S2")
    assert @runs.index("S2") < @runs.index("A0")
    assert @runs.index("S2") < @runs.index("B0")
    assert @runs.index("A0") < @runs.index("A1")
    assert @runs.index("A1") < @runs.index("A2")
    assert @runs.index("B0") < @runs.index("B1")
    assert @runs.index("B1") < @runs.index("B2")
  end
end


