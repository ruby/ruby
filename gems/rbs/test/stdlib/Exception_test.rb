require_relative "test_helper"

class ExceptionTest < StdlibTest
  target Exception
  using hook.refinement

  def test_full_message
    Exception.new.full_message
    Exception.new.full_message(highlight: true)
    Exception.new.full_message(highlight: false)
    Exception.new.full_message(order: :top)
    Exception.new.full_message(order: :bottom)
  end

  def test_to_tty
    Exception.to_tty?
  end

  def test_class_exception
    Exception.exception
    Exception.exception('test')
    NameError.exception
  end

  def test_double_equal
    Exception.new == Exception.new
  end

  def test_backtrace
    Exception.new.backtrace

    begin
      raise
    rescue => e
      e.backtrace
    end
  end

  def test_backtrace_locations
    Exception.new.backtrace_locations

    begin
      raise
    rescue => e
      e.backtrace_locations
    end
  end

  def test_cause
    Exception.new.cause

    begin
      raise
    rescue => e
      e.cause
    end
  end

  def test_exception
    Exception.new.exception
    Exception.new.exception('test')
  end

  def test_inspect
    Exception.new.inspect
  end

  def test_message
    Exception.new.message
  end

  def test_set_backtrace
    Exception.new.set_backtrace("foo")
    Exception.new.set_backtrace(["foo", "bar"])
  end

  def test_to_s
    Exception.new.to_s
  end
end
