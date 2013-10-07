require 'test/unit'
require '-test-/debug'

class C
  def self.bar(block)
    block.call
  end

  def foo(block)
    self.class.bar(block)
  end
end

class TestProfileFrames < Test::Unit::TestCase
  def test_profile_frames
    frames = Fiber.new{
      Fiber.yield C.new.foo(lambda{ Bug::Debug.profile_frames(0, 10) })
    }.resume

    assert_equal(4, frames.size)

    labels = [
      "block (2 levels) in test_profile_frames",
      "bar",
      "foo",
      "block in test_profile_frames",
    ]
    base_labels = [
      "test_profile_frames",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    classes = [
      TestProfileFrames,
      C, # singleton method
      C,
      TestProfileFrames,
    ]
    singleton_method_p = [
      false, true, false, false, false,
    ]

    frames.each.with_index{|(path, absolute_path, label, base_label, first_lineno, classpath, singleton_p), i|
      err_msg = "#{i}th frame"
      assert_equal(__FILE__, path, err_msg)
      assert_equal(__FILE__, absolute_path, err_msg)
      assert_equal(labels[i], label, err_msg)
      assert_equal(base_labels[i], base_label, err_msg)
      assert_equal(classes[i].to_s, classpath, err_msg)
      assert_equal(singleton_method_p[i], singleton_p, err_msg)
    }
  end
end
