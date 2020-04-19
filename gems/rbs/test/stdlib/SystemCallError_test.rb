require_relative "test_helper"

class SystemCallErrorTest < StdlibTest
  target SystemCallError
  using hook.refinement

  def test_initialize
    SystemCallError.new('hi', 0)
    a = SystemCallError.new(ToStr.new('hi'), 0)
    a.errno
    a.message
  end

  def test_errno
    begin
      raise Errno::ENOENT, 'test'
    rescue SystemCallError => exception
      exception.errno
    end

    begin
      raise SystemCallError.new('test', 3)
    rescue SystemCallError => exception
      exception.errno
    end
  end
end
