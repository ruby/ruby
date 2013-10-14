require 'test/unit'
require '-test-/debug'

class SampleClassForTestProfileFrames
  class Sample2
    def baz(block)
      block.call
    end
  end

  def self.bar(block)
    Sample2.new.baz(block)
  end

  def foo(block)
    self.class.bar(block)
  end
end

class TestProfileFrames < Test::Unit::TestCase
  def test_profile_frames
    frames = Fiber.new{
      Fiber.yield SampleClassForTestProfileFrames.new.foo(lambda{ Bug::Debug.profile_frames(0, 10) })
    }.resume

    labels = [
      "block (2 levels) in test_profile_frames",
      "baz",
      "bar",
      "foo",
      "block in test_profile_frames",
    ]
    base_labels = [
      "test_profile_frames",
      "baz",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    full_labels = [
      "block (2 levels) in TestProfileFrames#test_profile_frames",
      "SampleClassForTestProfileFrames::Sample2#baz",
      "SampleClassForTestProfileFrames.bar",
      "SampleClassForTestProfileFrames#foo",
      "block in TestProfileFrames#test_profile_frames",
    ]
    classes = [
      TestProfileFrames,
      SampleClassForTestProfileFrames::Sample2,
      SampleClassForTestProfileFrames, # singleton method
      SampleClassForTestProfileFrames,
      TestProfileFrames,
    ]
    singleton_method_p = [
      false, false, true, false, false, false,
    ]
    method_names = [
      "test_profile_frames",
      "baz",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    qualified_method_names = [
      "TestProfileFrames#test_profile_frames",
      "SampleClassForTestProfileFrames::Sample2#baz",
      "SampleClassForTestProfileFrames.bar",
      "SampleClassForTestProfileFrames#foo",
      "TestProfileFrames#test_profile_frames",
    ]

    # pp frames

    assert_equal(labels.size, frames.size)

    frames.each.with_index{|(path, absolute_path, label, base_label, full_label, first_lineno,
                            classpath, singleton_p, method_name, qualified_method_name), i|
      err_msg = "#{i}th frame"
      assert_equal(__FILE__, path, err_msg)
      assert_equal(__FILE__, absolute_path, err_msg)
      assert_equal(labels[i], label, err_msg)
      assert_equal(base_labels[i], base_label, err_msg)
      assert_equal(full_labels[i], full_label, err_msg)
      assert_equal(classes[i].to_s, classpath, err_msg)
      assert_equal(singleton_method_p[i], singleton_p, err_msg)
      assert_equal(method_names[i], method_name, err_msg)
      assert_equal(qualified_method_names[i], qualified_method_name, err_msg)
    }
  end
end
