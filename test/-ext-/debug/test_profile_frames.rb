# frozen_string_literal: false
require 'test/unit'
require '-test-/debug'

class SampleClassForTestProfileFrames
  class << self
    attr_accessor :sample4
  end

  self.sample4 = Module.new do
    def self.corge(block)
      Sample2.new.baz(block)
    end
  end

  class Sample2
    def baz(block)
      instance_eval "def zab(block) block.call end"
      [self, zab(block)]
    end
  end

  module Sample3
    class << self
      def qux(block)
        SampleClassForTestProfileFrames.sample4.corge(block)
      end
    end
  end

  def self.bar(block)
    Sample3.qux(block)
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
      nil,
      "test_profile_frames",
      "zab",
      "baz",
      "corge",
      "qux",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    base_labels = [
      nil,
      "test_profile_frames",
      "zab",
      "baz",
      "corge",
      "qux",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    full_labels = [
      "Bug::Debug.profile_frames",
      "TestProfileFrames#test_profile_frames",
      "#{obj.inspect}.zab",
      "SampleClassForTestProfileFrames::Sample2#baz",
      "#{SampleClassForTestProfileFrames.sample4.inspect}.corge",
      "SampleClassForTestProfileFrames::Sample3.qux",
      "SampleClassForTestProfileFrames.bar",
      "SampleClassForTestProfileFrames#foo",
      "TestProfileFrames#test_profile_frames",
    ]
    classes = [
      Bug::Debug,
      TestProfileFrames,
      obj,
      SampleClassForTestProfileFrames::Sample2,
      SampleClassForTestProfileFrames.sample4,
      SampleClassForTestProfileFrames::Sample3,
      SampleClassForTestProfileFrames, # singleton method
      SampleClassForTestProfileFrames,
      TestProfileFrames,
    ]
    singleton_method_p = [
      true, false, true, false, true, true, true, false, false, false,
    ]
    method_names = [
      "profile_frames",
      "test_profile_frames",
      "zab",
      "baz",
      "corge",
      "qux",
      "bar",
      "foo",
      "test_profile_frames",
    ]
    qualified_method_names = [
      "Bug::Debug.profile_frames",
      "TestProfileFrames#test_profile_frames",
      "#{obj.inspect}.zab",
      "SampleClassForTestProfileFrames::Sample2#baz",
      "#{SampleClassForTestProfileFrames.sample4.inspect}.corge",
      "SampleClassForTestProfileFrames::Sample3.qux",
      "SampleClassForTestProfileFrames.bar",
      "SampleClassForTestProfileFrames#foo",
      "TestProfileFrames#test_profile_frames",
    ]
    paths = [ nil, file=__FILE__, "(eval)", file, file, file, file, file, file, nil ]
    absolute_paths = [ "<cfunc>", file, nil, file, file, file, file, file, file, nil ]

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
      assert_equal(qualified_method_names[i], qualified_method_name, err_msg)
      assert_equal(full_labels[i], full_label, err_msg)
      assert_match(classes[i].inspect, classpath, err_msg)
      if label == method_name
        c = classes[i]
        m = singleton_p ? c.method(method_name) : c.instance_method(method_name)
        assert_equal(m.source_location[1], first_lineno, err_msg)
      end
    }
  end

  def test_matches_backtrace_locations_main_thread
    assert_equal(Thread.current, Thread.main)

    # Keep these in the same line, so the backtraces match exactly
    backtrace_locations, profile_frames = [Thread.current.backtrace_locations, Bug::Debug.profile_frames(0, 100)]

    assert_equal(backtrace_locations.size, profile_frames.size)

    # The first entries are not going to match, since one is #backtrace_locations and the other #profile_frames
    backtrace_locations.shift
    profile_frames.shift

    # The rest of the stack is expected to look the same...
    backtrace_locations.zip(profile_frames).each.with_index do |(location, (path, absolute_path, _, base_label, _, _, _, _, _, _, lineno)), i|
      next if absolute_path == "<cfunc>" # ...except for cfunc frames

      err_msg = "#{i}th frame"
      assert_equal(location.absolute_path, absolute_path, err_msg)
      assert_equal(location.base_label, base_label, err_msg)
      assert_equal(location.lineno, lineno, err_msg)
      assert_equal(location.path, path, err_msg)
    end
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
