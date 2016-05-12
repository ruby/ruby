# frozen_string_literal: false
require 'test/unit'
require '-test-/debug'

class SampleClassForTestProfileFrames
  class Sample2
    def baz(block)
      instance_eval "def zab(block) block.call end"
      [self, zab(block)]
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
    obj, frames = Fiber.new{
      Fiber.yield SampleClassForTestProfileFrames.new.foo(lambda{ Bug::Debug.profile_frames(0, 10) })
    }.resume

    labels = [
      "test_profile_frames",
      "zab",
      "baz",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    base_labels = [
      "test_profile_frames",
      "zab",
      "baz",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    full_labels = [
      "TestProfileFrames#test_profile_frames",
      "#{obj.inspect}.zab",
      "SampleClassForTestProfileFrames::Sample2#baz",
      "SampleClassForTestProfileFrames.bar",
      "SampleClassForTestProfileFrames#foo",
      "TestProfileFrames#test_profile_frames",
    ]
    classes = [
      TestProfileFrames,
      obj,
      SampleClassForTestProfileFrames::Sample2,
      SampleClassForTestProfileFrames, # singleton method
      SampleClassForTestProfileFrames,
      TestProfileFrames,
    ]
    singleton_method_p = [
      false, true, false, true, false, false, false,
    ]
    method_names = [
      "test_profile_frames",
      "zab",
      "baz",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    qualified_method_names = [
      "TestProfileFrames#test_profile_frames",
      "#{obj.inspect}.zab",
      "SampleClassForTestProfileFrames::Sample2#baz",
      "SampleClassForTestProfileFrames.bar",
      "SampleClassForTestProfileFrames#foo",
      "TestProfileFrames#test_profile_frames",
    ]
    paths = [ file=__FILE__, "(eval)", file, file, file, file ]
    absolute_paths = [ file, nil, file, file, file, file ]

    # pp frames

    assert_equal(labels.size, frames.size)

    frames.each.with_index{|(path, absolute_path, label, base_label, full_label, first_lineno,
                            classpath, singleton_p, method_name, qualified_method_name), i|
      err_msg = "#{i}th frame"
      assert_equal(paths[i], path, err_msg)
      assert_equal(absolute_paths[i], absolute_path, err_msg)
      assert_equal(labels[i], label, err_msg)
      assert_equal(base_labels[i], base_label, err_msg)
      assert_equal(singleton_method_p[i], singleton_p, err_msg)
      assert_equal(method_names[i], method_name, err_msg)
      assert_match(qualified_method_names[i], qualified_method_name, err_msg)
      assert_match(full_labels[i], full_label, err_msg)
      assert_match(classes[i].inspect, classpath, err_msg)
      if label == method_name
        c = classes[i]
        m = singleton_p ? c.method(method_name) : c.instance_method(method_name)
        assert_equal(m.source_location[1], first_lineno, err_msg)
      end
    }
  end

  def test_ifunc_frame
    bug11851 = '[ruby-core:72409] [Bug #11851]'
    assert_ruby_status([], <<~'end;', bug11851) # do
      require '-test-/debug'
      class A
        include Bug::Debug
        def x
          profile_frames(0, 10)
        end
      end
      def a
        [A.new].each(&:x)
      end
      a
    end;
  end
end
