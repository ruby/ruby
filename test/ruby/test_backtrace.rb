# frozen_string_literal: false
require 'test/unit'
require 'thread'
require 'tempfile'

class TestBacktrace < Test::Unit::TestCase
  def test_exception
    bt = Fiber.new{
      begin
        raise
      rescue => e
        e.backtrace
      end
    }.resume
    assert_equal(1, bt.size)
    assert_match(/.+:\d+:.+/, bt[0])
  end

  def helper_test_exception_backtrace_locations
    raise
  end

  def test_exception_backtrace_locations
    backtrace, backtrace_locations = Fiber.new{
      begin
        raise
      rescue => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})

    backtrace, backtrace_locations = Fiber.new{
      begin
        begin
          helper_test_exception_backtrace_locations
        rescue
          raise
        end
      rescue => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})
  end

  def call_helper_test_exception_backtrace_locations
    helper_test_exception_backtrace_locations(:bad_argument)
  end

  def test_argument_error_backtrace_locations
    backtrace, backtrace_locations = Fiber.new{
      begin
        helper_test_exception_backtrace_locations(1)
      rescue ArgumentError => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})

    backtrace, backtrace_locations = Fiber.new{
      begin
        call_helper_test_exception_backtrace_locations
      rescue ArgumentError => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})
  end

  def test_caller_lev
    cs = []
    Fiber.new{
      Proc.new{
        cs << caller(0)
        cs << caller(1)
        cs << caller(2)
        cs << caller(3)
        cs << caller(4)
        cs << caller(5)
      }.call
    }.resume
    assert_equal(2, cs[0].size)
    assert_equal(1, cs[1].size)
    assert_equal(0, cs[2].size)
    assert_equal(nil, cs[3])
    assert_equal(nil, cs[4])

    #
    max = 7
    rec = lambda{|n|
      if n > 0
        1.times{
          rec[n-1]
        }
      else
        (max*3).times{|i|
          total_size = caller(0).size
          c = caller(i)
          if c
            assert_equal(total_size - i, caller(i).size, "[ruby-dev:45673]")
          end
        }
      end
    }
    Fiber.new{
      rec[max]
    }.resume
  end

  def test_caller_lev_and_n
    m = 10
    rec = lambda{|n|
      if n < 0
        (m*6).times{|lev|
          (m*6).times{|i|
            t = caller(0).size
            r = caller(lev, i)
            r = r.size if r.respond_to? :size

            # STDERR.puts [t, lev, i, r].inspect
            if i == 0
              assert_equal(0, r, [t, lev, i, r].inspect)
            elsif t < lev
              assert_equal(nil, r, [t, lev, i, r].inspect)
            else
              if t - lev > i
                assert_equal(i, r, [t, lev, i, r].inspect)
              else
                assert_equal(t - lev, r, [t, lev, i, r].inspect)
              end
            end
          }
        }
      else
        rec[n-1]
      end
    }
    rec[m]
  end

  def test_caller_with_nil_length
    assert_equal caller(0), caller(0, nil)
  end

  def test_caller_locations
    cs = caller(0); locs = caller_locations(0).map{|loc|
      loc.to_s
    }
    assert_equal(cs, locs)
  end

  def test_caller_locations_with_range
    cs = caller(0,2); locs = caller_locations(0..1).map { |loc|
      loc.to_s
    }
    assert_equal(cs, locs)
  end

  def test_caller_locations_to_s_inspect
    cs = caller(0); locs = caller_locations(0)
    cs.zip(locs){|str, loc|
      assert_equal(str, loc.to_s)
      assert_equal(str.inspect, loc.inspect)
    }
  end

  def test_caller_locations_path
    loc, = caller_locations(0, 1)
    assert_equal(__FILE__, loc.path)
    Tempfile.create(%w"caller_locations .rb") do |f|
      f.puts "caller_locations(0, 1)[0].tap {|loc| puts loc.path}"
      f.close
      dir, base = File.split(f.path)
      assert_in_out_err(["-C", dir, base], "", [base])
    end
  end

  def test_caller_locations_absolute_path
    loc, = caller_locations(0, 1)
    assert_equal(__FILE__, loc.absolute_path)
    Tempfile.create(%w"caller_locations .rb") do |f|
      f.puts "caller_locations(0, 1)[0].tap {|loc| puts loc.absolute_path}"
      f.close
      assert_in_out_err(["-C", *File.split(f.path)], "", [File.realpath(f.path)])
    end
  end

  def test_caller_locations_lineno
    loc, = caller_locations(0, 1)
    assert_equal(__LINE__-1, loc.lineno)
    Tempfile.create(%w"caller_locations .rb") do |f|
      f.puts "caller_locations(0, 1)[0].tap {|loc| puts loc.lineno}"
      f.close
      assert_in_out_err(["-C", *File.split(f.path)], "", ["1"])
    end
  end

  def test_caller_locations_base_label
    assert_equal("#{__method__}", caller_locations(0, 1)[0].base_label)
    loc, = tap {break caller_locations(0, 1)}
    assert_equal("#{__method__}", loc.base_label)
    begin
      raise
    rescue
      assert_equal("#{__method__}", caller_locations(0, 1)[0].base_label)
    end
  end

  def test_caller_locations_label
    assert_equal("#{__method__}", caller_locations(0, 1)[0].label)
    loc, = tap {break caller_locations(0, 1)}
    assert_equal("block in #{__method__}", loc.label)
    begin
      raise
    rescue
      assert_equal("rescue in #{__method__}", caller_locations(0, 1)[0].label)
    end
  end

  def th_rec q, n=10
    if n > 1
      th_rec q, n-1
    else
      q.pop
    end
  end

  def test_thread_backtrace
    begin
      q = Thread::Queue.new
      th = Thread.new{
        th_rec q
      }
      sleep 0.5
      th_backtrace = th.backtrace
      th_locations = th.backtrace_locations

      assert_equal(10, th_backtrace.count{|e| e =~ /th_rec/})
      assert_equal(th_backtrace, th_locations.map{|e| e.to_s})
      assert_equal(th_backtrace, th.backtrace(0))
      assert_equal(th_locations.map{|e| e.to_s},
                   th.backtrace_locations(0).map{|e| e.to_s})
      th_backtrace.size.times{|n|
        assert_equal(n, th.backtrace(0, n).size)
        assert_equal(n, th.backtrace_locations(0, n).size)
      }
      n = th_backtrace.size
      assert_equal(n, th.backtrace(0, n + 1).size)
      assert_equal(n, th.backtrace_locations(0, n + 1).size)
    ensure
      q << true
      th.join
    end
  end

  def test_thread_backtrace_locations_with_range
    begin
      q = Thread::Queue.new
      th = Thread.new{
        th_rec q
      }
      sleep 0.5
      bt = th.backtrace(0,2)
      locs = th.backtrace_locations(0..1).map { |loc|
        loc.to_s
      }
      assert_equal(bt, locs)
    ensure
      q << true
      th.join
    end
  end

  def test_core_backtrace_alias
    obj = BasicObject.new
    e = assert_raise(NameError) do
      class << obj
        alias foo bar
      end
    end
    assert_not_match(/\Acore#/, e.backtrace_locations[0].base_label)
  end

  def test_core_backtrace_undef
    obj = BasicObject.new
    e = assert_raise(NameError) do
      class << obj
        undef foo
      end
    end
    assert_not_match(/\Acore#/, e.backtrace_locations[0].base_label)
  end

  def test_core_backtrace_hash_merge
    e = assert_raise(TypeError) do
      {**nil}
    end
    assert_not_match(/\Acore#/, e.backtrace_locations[0].base_label)
  end
end
