# frozen_string_literal: false
begin
  require '-test-/popen_deadlock/infinite_loop_dlsym'
rescue LoadError
  skip = true
end

class TestPopenDeadlock < Test::Unit::TestCase

  # [Bug #11265]
  def assert_popen_without_deadlock
    assert_separately([], <<-"end;", timeout: 90) #do
        require '-test-/popen_deadlock/infinite_loop_dlsym'

        bug = '11265'.freeze
        begin
          t = Thread.new {
            Thread.current.__infinite_loop_dlsym__("_ex_unwind")
          }
          str = IO.popen([ 'echo', bug ], 'r+') { |io| io.read }
          assert_equal(bug, str.chomp)
        ensure
          t.kill if t
        end
    end;
  end
  private :assert_popen_without_deadlock

  # 10 test methods are defined for showing progess reports
  10.times do |i|
    define_method("test_popen_without_deadlock_#{i}") {
      assert_popen_without_deadlock
    }
  end

end unless skip #class TestPopenDeadlock
