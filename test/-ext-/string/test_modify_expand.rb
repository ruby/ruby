require 'test/unit'
require "-test-/string/string"
require_relative '../../ruby/envutil'

class Test_StringModifyExpand < Test::Unit::TestCase
  def test_modify_expand_memory_leak
    before = after = nil
    args = [
      "--disable=gems", "-r-test-/string/string",
      "-I"+File.expand_path("../../..", __FILE__),
      "-rruby/memory_status",
      "-e", <<-CMD
      s=Bug::String.new
      size=Memory::Status.new.size
      puts size
      10.times{s.modify_expand!(size)}
      s.replace("")
      puts Memory::Status.new.size
    CMD
    ]
    status = EnvUtil.invoke_ruby(args, "", true) do |in_p, out_p, err_p, pid|
      before, after = out_p.readlines.map(&:to_i)
      Process.wait(pid)
      $?
    end
    assert_equal(true, status.success?)
    assert_operator after.fdiv(before), :<, 2
  end
end
