# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'

class TestTracer < Test::Unit::TestCase
  include EnvUtil

  def test_tracer_with_option_r
    assert_in_out_err(%w[-rtracer -e 1]) do |(*lines),|
      case lines.size
      when 1
        # do nothing
      else
        assert_match(%r{rubygems/core_ext/kernel_require\.rb:\d+:Kernel:<:}, lines[0])
      end
      assert_equal "#0:-e:1::-: 1", lines.last
    end
  end

  def test_tracer_with_option_r_without_gems
    assert_in_out_err(%w[--disable-gems -rtracer -e 1]) do |(*lines),|
      assert_equal 1, lines.size, "unexpected output from `ruby --disable-gems -rtracer -e 1`"
      assert_equal "#0:-e:1::-: 1", lines.last
    end
  end

  def test_tracer_with_require
    Dir.mktmpdir("test_ruby_tracer") do |dir|
      script = File.join(dir, "require_tracer.rb")
      open(script, "w") do |f|
        f.print <<-EOF
require 'tracer'
1
        EOF
      end
      assert_in_out_err([script]) do |(*lines),|
        assert_empty(lines)
      end
    end
  end

  def test_tracer_with_require_without_gems
    Dir.mktmpdir("test_ruby_tracer") do |dir|
      script = File.join(dir, "require_tracer.rb")
      open(script, "w") do |f|
        f.print <<-EOF
require 'tracer'
1
        EOF
      end
      assert_in_out_err(["--disable-gems", script]) do |(*lines),|
        assert_empty(lines)
      end
    end
  end

  def test_tracer_by_add_filter_with_block
    Dir.mktmpdir("test_ruby_tracer") do |dir|
      script = File.join(dir, "require_tracer.rb")
      open(script, "w") do |f|
        f.print <<-'EOF'
require 'tracer'

class Hoge
  def Hoge.fuga(i)
    "fuga #{i}"
  end
end

Tracer.add_filter {|event, file, line, id, binding, klass|
  event =~ /line/ and klass.to_s =~ /hoge/i
}
Tracer.on
for i in 0..3
  puts Hoge.fuga(i) if i % 3 == 0
end
Tracer.off
        EOF
      end
      assert_in_out_err([script]) do |(*lines), err|
        expected = [
          "#0:#{script}:5:Hoge:-:     \"fuga \#{i}\"",
          "fuga 0",
          "#0:#{script}:5:Hoge:-:     \"fuga \#{i}\"",
          "fuga 3"
        ]
        assert_equal(expected, lines)
        assert_empty(err)
      end
    end
  end

  def test_tracer_by_add_filter_with_proc
    Dir.mktmpdir("test_ruby_tracer") do |dir|
      script = File.join(dir, "require_tracer.rb")
      open(script, "w") do |f|
        f.print <<-'EOF'
require 'tracer'

class Hoge
  def Hoge.fuga(i)
    "fuga #{i}"
  end
end

a_proc_to_add_filter = proc {|event, file, line, id, binding, klass|
  event =~ /line/ and klass.to_s =~ /hoge/i
}
Tracer.add_filter(a_proc_to_add_filter)
Tracer.on
for i in 0..3
  puts Hoge.fuga(i) if i % 3 == 0
end
Tracer.off
        EOF
      end
      assert_in_out_err([script]) do |(*lines), err|
        expected = [
          "#0:#{script}:5:Hoge:-:     \"fuga \#{i}\"",
          "fuga 0",
          "#0:#{script}:5:Hoge:-:     \"fuga \#{i}\"",
          "fuga 3"
        ]
        assert_equal(expected, lines)
        assert_empty(err)
      end
    end
  end

  def test_tracer_by_set_get_line_procs_with_block
    Dir.mktmpdir("test_ruby_tracer") do |dir|
      dummy_script = File.join(dir, "dummy.rb")
      open(dummy_script, "w") do |f|
        f.print <<-'EOF'
class Dummy
  def initialize
    @number = 135
  end
  attr :number
end
        EOF
      end
      dummy_script = File.realpath dummy_script
      script = File.join(dir, "require_tracer.rb")
      open(script, "w") do |f|
        f.print <<-EOF
require 'tracer'

Tracer.set_get_line_procs('#{dummy_script}') { |line|
  str = %{\\n}
  str = %{!!\\n} if line >= 3 and line <= 6
  str
}
Tracer.on
require_relative 'dummy'

dm = Dummy.new
puts dm.number
        EOF
      end
      assert_in_out_err([script]) do |(*lines), err|
        expected = [
          "#0:#{script}:9::-: require_relative 'dummy'",
          "#0:#{dummy_script}:1::-: ",
          "#0:#{dummy_script}:1::C: ",
          "#0:#{dummy_script}:2::-: ",
          "#0:#{dummy_script}:5::-: !!",
          "#0:#{dummy_script}:6::E: !!",
          "#0:#{script}:11::-: dm = Dummy.new",
          "#0:#{dummy_script}:2:Dummy:>: ",
          "#0:#{dummy_script}:3:Dummy:-: !!",
          "#0:#{dummy_script}:4:Dummy:<: !!",
          "#0:#{script}:12::-: puts dm.number",
          "135"
        ]
        assert_equal(expected, lines)
        assert_empty(err)
      end
    end
  end

  def test_tracer_by_set_get_line_procs_with_proc
    Dir.mktmpdir("test_ruby_tracer") do |dir|
      dummy_script = File.join(dir, "dummy.rb")
      open(dummy_script, "w") do |f|
        f.print <<-'EOF'
class Dummy
  def initialize
    @number = 135
  end
  attr :number
end
        EOF
      end
      dummy_script = File.realpath dummy_script
      script = File.join(dir, "require_tracer.rb")
      open(script, "w") do |f|
        f.print <<-EOF
require 'tracer'

a_proc_to_set_get_line_procs = proc { |line|
  str = %{\\n}
  str = %{!!\\n} if line >= 3 and line <= 6
  str
}
Tracer.set_get_line_procs('#{dummy_script}', a_proc_to_set_get_line_procs)
Tracer.on
require_relative 'dummy'

dm = Dummy.new
puts dm.number
        EOF
      end
      assert_in_out_err([script]) do |(*lines), err|
        expected = [
          "#0:#{script}:10::-: require_relative 'dummy'",
          "#0:#{dummy_script}:1::-: ",
          "#0:#{dummy_script}:1::C: ",
          "#0:#{dummy_script}:2::-: ",
          "#0:#{dummy_script}:5::-: !!",
          "#0:#{dummy_script}:6::E: !!",
          "#0:#{script}:12::-: dm = Dummy.new",
          "#0:#{dummy_script}:2:Dummy:>: ",
          "#0:#{dummy_script}:3:Dummy:-: !!",
          "#0:#{dummy_script}:4:Dummy:<: !!",
          "#0:#{script}:13::-: puts dm.number",
          "135"
        ]
        assert_equal(expected, lines)
        assert_empty(err)
      end
    end
  end
end
