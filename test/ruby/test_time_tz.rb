# frozen_string_literal: false
require 'test/unit'
require '-test-/time'

class TestTimeTZ < Test::Unit::TestCase
  has_right_tz = true
  has_lisbon_tz = true
  force_tz_test = ENV["RUBY_FORCE_TIME_TZ_TEST"] == "yes"
  case RUBY_PLATFORM
  when /linux/
    force_tz_test = true
  when /darwin|freebsd|openbsd/
    has_lisbon_tz = false
    force_tz_test = true
  end

  if force_tz_test
    module Util
      def with_tz(tz)
        old = ENV["TZ"]
        begin
          ENV["TZ"] = tz
          yield
        ensure
          ENV["TZ"] = old
        end
      end
    end
  else
    module Util
      def with_tz(tz)
        if ENV["TZ"] == tz
          yield
        end
      end
    end
  end

  module Util
    def have_tz_offset?(tz)
      with_tz(tz) {!Time.now.utc_offset.zero?}
    end

    def format_gmtoff(gmtoff, colon=false)
      if gmtoff < 0
        expected = "-"
        gmtoff = -gmtoff
      else
        expected = "+"
      end
      gmtoff /= 60
      expected << "%02d" % [gmtoff / 60]
      expected << ":" if colon
      expected << "%02d" % [gmtoff % 60]
      expected
    end

    def format_gmtoff2(gmtoff)
      if gmtoff < 0
        expected = "-"
        gmtoff = -gmtoff
      else
        expected = "+"
      end
      expected << "%02d:%02d:%02d" % [gmtoff / 3600, gmtoff % 3600 / 60, gmtoff % 60]
      expected
    end

    def group_by(e, &block)
      if e.respond_to? :group_by
        e.group_by(&block)
      else
        h = {}
        e.each {|o|
          (h[yield(o)] ||= []) << o
        }
        h
      end
    end

  end

  include Util
  extend Util

  has_right_tz &&= have_tz_offset?("right/America/Los_Angeles")
  has_lisbon_tz &&= have_tz_offset?("Europe/Lisbon")
  CORRECT_TOKYO_DST_1951 = with_tz("Asia/Tokyo") {
    if Time.local(1951, 5, 6, 12, 0, 0).dst? # noon, DST
      if Time.local(1951, 5, 6, 1, 0, 0).dst? # DST with fixed tzdata
        Time.local(1951, 9, 8, 23, 0, 0).dst? ? "2018f" : "2018e"
      end
    end
  }
  CORRECT_KIRITIMATI_SKIP_1994 = with_tz("Pacific/Kiritimati") {
    Time.local(1994, 12, 31, 0, 0, 0).year == 1995
  }

  def time_to_s(t)
    t.to_s
  end


  def assert_time_constructor(tz, expected, method, args, message=nil)
    m = message ? "#{message}\n" : ""
    m << "TZ=#{tz} Time.#{method}(#{args.map {|arg| arg.inspect }.join(', ')})"
    real = time_to_s(Time.send(method, *args))
    assert_equal(expected, real, m)
  end

  def test_localtime_zone
    t = with_tz("America/Los_Angeles") {
      Time.local(2000, 1, 1)
    }
    skip "force_tz_test is false on this environment" unless t
    z1 = t.zone
    z2 = with_tz(tz="Asia/Singapore") {
      t.localtime.zone
    }
    assert_equal(z2, z1)
  end

  def test_america_los_angeles
    with_tz(tz="America/Los_Angeles") {
      assert_time_constructor(tz, "2007-03-11 03:00:00 -0700", :local, [2007,3,11,2,0,0])
      assert_time_constructor(tz, "2007-03-11 03:59:59 -0700", :local, [2007,3,11,2,59,59])
      assert_equal("PST", Time.new(0x1_0000_0000_0000_0000, 1).zone)
      assert_equal("PDT", Time.new(0x1_0000_0000_0000_0000, 8).zone)
      assert_equal(false, Time.new(0x1_0000_0000_0000_0000, 1).isdst)
      assert_equal(true, Time.new(0x1_0000_0000_0000_0000, 8).isdst)
    }
  end

  def test_america_managua
    with_tz(tz="America/Managua") {
      assert_time_constructor(tz, "1993-01-01 01:00:00 -0500", :local, [1993,1,1,0,0,0])
      assert_time_constructor(tz, "1993-01-01 01:59:59 -0500", :local, [1993,1,1,0,59,59])
    }
  end

  def test_asia_singapore
    with_tz(tz="Asia/Singapore") {
      assert_time_constructor(tz, "1981-12-31 23:59:59 +0730", :local, [1981,12,31,23,59,59])
      assert_time_constructor(tz, "1982-01-01 00:30:00 +0800", :local, [1982,1,1,0,0,0])
      assert_time_constructor(tz, "1982-01-01 00:59:59 +0800", :local, [1982,1,1,0,29,59])
      assert_time_constructor(tz, "1982-01-01 00:30:00 +0800", :local, [1982,1,1,0,30,0])
    }
  end

  def test_asia_tokyo
    with_tz(tz="Asia/Tokyo") {
      h = CORRECT_TOKYO_DST_1951 ? 0 : 2
      assert_time_constructor(tz, "1951-05-06 0#{h+1}:00:00 +1000", :local, [1951,5,6,h,0,0])
      assert_time_constructor(tz, "1951-05-06 0#{h+1}:59:59 +1000", :local, [1951,5,6,h,59,59])
      assert_time_constructor(tz, "2010-06-10 06:13:28 +0900", :local, [2010,6,10,6,13,28])
    }
  end

  def test_asia_kuala_lumpur
    with_tz(tz="Asia/Kuala_Lumpur") {
      assert_time_constructor(tz, "1933-01-01 00:20:00 +0720", :local, [1933])
    }
  end

  def test_canada_newfoundland
    with_tz(tz="America/St_Johns") {
      assert_time_constructor(tz, "2007-11-03 23:00:59 -0230", :new, [2007,11,3,23,0,59,:dst])
      assert_time_constructor(tz, "2007-11-03 23:01:00 -0230", :new, [2007,11,3,23,1,0,:dst])
      assert_time_constructor(tz, "2007-11-03 23:59:59 -0230", :new, [2007,11,3,23,59,59,:dst])
      assert_time_constructor(tz, "2007-11-04 00:00:00 -0230", :new, [2007,11,4,0,0,0,:dst])
      assert_time_constructor(tz, "2007-11-04 00:00:59 -0230", :new, [2007,11,4,0,0,59,:dst])
      assert_time_constructor(tz, "2007-11-03 23:01:00 -0330", :new, [2007,11,3,23,1,0,:std])
      assert_time_constructor(tz, "2007-11-03 23:59:59 -0330", :new, [2007,11,3,23,59,59,:std])
      assert_time_constructor(tz, "2007-11-04 00:00:59 -0330", :new, [2007,11,4,0,0,59,:std])
      assert_time_constructor(tz, "2007-11-04 00:01:00 -0330", :new, [2007,11,4,0,1,0,:std])
    }
  end

  def test_europe_brussels
    with_tz(tz="Europe/Brussels") {
      assert_time_constructor(tz, "1916-04-30 23:59:59 +0100", :local, [1916,4,30,23,59,59])
      assert_time_constructor(tz, "1916-05-01 01:00:00 +0200", :local, [1916,5,1], "[ruby-core:30672] [Bug #3411]")
      assert_time_constructor(tz, "1916-05-01 01:59:59 +0200", :local, [1916,5,1,0,59,59])
      assert_time_constructor(tz, "1916-05-01 01:00:00 +0200", :local, [1916,5,1,1,0,0])
      assert_time_constructor(tz, "1916-05-01 01:59:59 +0200", :local, [1916,5,1,1,59,59])
    }
  end

  def test_europe_berlin
    with_tz(tz="Europe/Berlin") {
      assert_time_constructor(tz, "2011-10-30 02:00:00 +0100", :local, [2011,10,30,2,0,0], "[ruby-core:67345] [Bug #10698]")
      assert_time_constructor(tz, "2011-10-30 02:00:00 +0100", :local, [0,0,2,30,10,2011,nil,nil,false,nil])
      assert_time_constructor(tz, "2011-10-30 02:00:00 +0200", :local, [0,0,2,30,10,2011,nil,nil,true,nil])
    }
  end

  def test_europe_lisbon
    with_tz("Europe/Lisbon") {
      assert_equal("LMT", Time.new(-0x1_0000_0000_0000_0000).zone)
    }
  end if has_lisbon_tz

  def test_pacific_kiritimati
    with_tz(tz="Pacific/Kiritimati") {
      assert_time_constructor(tz, "1994-12-30 00:00:00 -1000", :local, [1994,12,30,0,0,0])
      assert_time_constructor(tz, "1994-12-30 23:59:59 -1000", :local, [1994,12,30,23,59,59])
      if CORRECT_KIRITIMATI_SKIP_1994
        assert_time_constructor(tz, "1995-01-01 00:00:00 +1400", :local, [1994,12,31,0,0,0])
        assert_time_constructor(tz, "1995-01-01 23:59:59 +1400", :local, [1994,12,31,23,59,59])
        assert_time_constructor(tz, "1995-01-01 00:00:00 +1400", :local, [1995,1,1,0,0,0])
      else
        assert_time_constructor(tz, "1994-12-31 23:59:59 -1000", :local, [1994,12,31,23,59,59])
        assert_time_constructor(tz, "1995-01-02 00:00:00 +1400", :local, [1995,1,1,0,0,0])
        assert_time_constructor(tz, "1995-01-02 23:59:59 +1400", :local, [1995,1,1,23,59,59])
      end
      assert_time_constructor(tz, "1995-01-02 00:00:00 +1400", :local, [1995,1,2,0,0,0])
    }
  end

  def test_right_utc
    with_tz(tz="right/UTC") {
      assert_time_constructor(tz, "2008-12-31 23:59:59 UTC", :utc, [2008,12,31,23,59,59])
      assert_time_constructor(tz, "2008-12-31 23:59:60 UTC", :utc, [2008,12,31,23,59,60])
      assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2008,12,31,24,0,0])
      assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2009,1,1,0,0,0])
    }
  end if has_right_tz

  def test_right_utc_switching
    with_tz("UTC") { # ensure no leap second timezone
      assert_equal(4102444800, Time.utc(2100,1,1,0,0,0).to_i)
      with_tz(tz="right/UTC") {
        assert_time_constructor(tz, "2008-12-31 23:59:59 UTC", :utc, [2008,12,31,23,59,59])
        assert_time_constructor(tz, "2008-12-31 23:59:60 UTC", :utc, [2008,12,31,23,59,60])
        assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2008,12,31,24,0,0])
        assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2009,1,1,0,0,0])
        assert_not_equal(4102444800, Time.utc(2100,1,1,0,0,0).to_i)
      }
    }
    with_tz("right/UTC") {
      assert_not_equal(4102444800, Time.utc(2100,1,1,0,0,0).to_i)
      with_tz(tz="UTC") {
        assert_time_constructor(tz, "2008-12-31 23:59:59 UTC", :utc, [2008,12,31,23,59,59])
        assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2008,12,31,23,59,60])
        assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2008,12,31,24,0,0])
        assert_time_constructor(tz, "2009-01-01 00:00:00 UTC", :utc, [2009,1,1,0,0,0])
        assert_equal(4102444800, Time.utc(2100,1,1,0,0,0).to_i)
      }
    }
  end if has_right_tz

  def test_right_america_los_angeles
    with_tz(tz="right/America/Los_Angeles") {
      assert_time_constructor(tz, "2008-12-31 15:59:59 -0800", :local, [2008,12,31,15,59,59])
      assert_time_constructor(tz, "2008-12-31 15:59:60 -0800", :local, [2008,12,31,15,59,60])
      assert_time_constructor(tz, "2008-12-31 16:00:00 -0800", :local, [2008,12,31,16,0,0])
    }
  end if has_right_tz

  def test_utc_names
    assert_predicate(Time.new(2019, 1, 1, 0, 0, 0, "UTC"), :utc?)
    assert_predicate(Time.new(2019, 1, 1, 0, 0, 0, "utc"), :utc?)
    assert_predicate(Time.new(2019, 1, 1, 0, 0, 0, "Z"), :utc?)
  end

  def test_military_names
    assert_equal( +1*3600, Time.new(2019, 1, 1, 0, 0, 0, "A").gmtoff)
    assert_equal( +2*3600, Time.new(2019, 1, 1, 0, 0, 0, "B").gmtoff)
    assert_equal( +3*3600, Time.new(2019, 1, 1, 0, 0, 0, "C").gmtoff)
    assert_equal( +4*3600, Time.new(2019, 1, 1, 0, 0, 0, "D").gmtoff)
    assert_equal( +5*3600, Time.new(2019, 1, 1, 0, 0, 0, "E").gmtoff)
    assert_equal( +6*3600, Time.new(2019, 1, 1, 0, 0, 0, "F").gmtoff)
    assert_equal( +7*3600, Time.new(2019, 1, 1, 0, 0, 0, "G").gmtoff)
    assert_equal( +8*3600, Time.new(2019, 1, 1, 0, 0, 0, "H").gmtoff)
    assert_equal( +9*3600, Time.new(2019, 1, 1, 0, 0, 0, "I").gmtoff)
    assert_equal(+10*3600, Time.new(2019, 1, 1, 0, 0, 0, "K").gmtoff)
    assert_equal(+11*3600, Time.new(2019, 1, 1, 0, 0, 0, "L").gmtoff)
    assert_equal(+12*3600, Time.new(2019, 1, 1, 0, 0, 0, "M").gmtoff)
    assert_equal( -1*3600, Time.new(2019, 1, 1, 0, 0, 0, "N").gmtoff)
    assert_equal( -2*3600, Time.new(2019, 1, 1, 0, 0, 0, "O").gmtoff)
    assert_equal( -3*3600, Time.new(2019, 1, 1, 0, 0, 0, "P").gmtoff)
    assert_equal( -4*3600, Time.new(2019, 1, 1, 0, 0, 0, "Q").gmtoff)
    assert_equal( -5*3600, Time.new(2019, 1, 1, 0, 0, 0, "R").gmtoff)
    assert_equal( -6*3600, Time.new(2019, 1, 1, 0, 0, 0, "S").gmtoff)
    assert_equal( -7*3600, Time.new(2019, 1, 1, 0, 0, 0, "T").gmtoff)
    assert_equal( -8*3600, Time.new(2019, 1, 1, 0, 0, 0, "U").gmtoff)
    assert_equal( -9*3600, Time.new(2019, 1, 1, 0, 0, 0, "V").gmtoff)
    assert_equal(-10*3600, Time.new(2019, 1, 1, 0, 0, 0, "W").gmtoff)
    assert_equal(-11*3600, Time.new(2019, 1, 1, 0, 0, 0, "X").gmtoff)
    assert_equal(-12*3600, Time.new(2019, 1, 1, 0, 0, 0, "Y").gmtoff)
    assert_equal(       0, Time.new(2019, 1, 1, 0, 0, 0, "Z").gmtoff)

    assert_equal( +1*3600, Time.at(0, in: "A").gmtoff)
    assert_equal( +2*3600, Time.at(0, in: "B").gmtoff)
    assert_equal( +3*3600, Time.at(0, in: "C").gmtoff)
    assert_equal( +4*3600, Time.at(0, in: "D").gmtoff)
    assert_equal( +5*3600, Time.at(0, in: "E").gmtoff)
    assert_equal( +6*3600, Time.at(0, in: "F").gmtoff)
    assert_equal( +7*3600, Time.at(0, in: "G").gmtoff)
    assert_equal( +8*3600, Time.at(0, in: "H").gmtoff)
    assert_equal( +9*3600, Time.at(0, in: "I").gmtoff)
    assert_equal(+10*3600, Time.at(0, in: "K").gmtoff)
    assert_equal(+11*3600, Time.at(0, in: "L").gmtoff)
    assert_equal(+12*3600, Time.at(0, in: "M").gmtoff)
    assert_equal( -1*3600, Time.at(0, in: "N").gmtoff)
    assert_equal( -2*3600, Time.at(0, in: "O").gmtoff)
    assert_equal( -3*3600, Time.at(0, in: "P").gmtoff)
    assert_equal( -4*3600, Time.at(0, in: "Q").gmtoff)
    assert_equal( -5*3600, Time.at(0, in: "R").gmtoff)
    assert_equal( -6*3600, Time.at(0, in: "S").gmtoff)
    assert_equal( -7*3600, Time.at(0, in: "T").gmtoff)
    assert_equal( -8*3600, Time.at(0, in: "U").gmtoff)
    assert_equal( -9*3600, Time.at(0, in: "V").gmtoff)
    assert_equal(-10*3600, Time.at(0, in: "W").gmtoff)
    assert_equal(-11*3600, Time.at(0, in: "X").gmtoff)
    assert_equal(-12*3600, Time.at(0, in: "Y").gmtoff)
    assert_equal(       0, Time.at(0, in: "Z").gmtoff)
  end

  MON2NUM = {
    "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6,
    "Jul" => 7, "Aug" => 8, "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
  }

  @testnum = 0
  def self.gen_test_name(hint)
    @testnum += 1
    s = "test_gen_#{@testnum}"
    s.sub(/gen_/) { "gen" + "_#{hint}_".gsub(/[^0-9A-Za-z]+/, '_') }
  end

  def self.parse_zdump_line(line)
    return nil if /\A\#/ =~ line || /\A\s*\z/ =~ line
    if /\A(\S+)\s+
        \S+\s+(\S+)\s+(\d+)\s+(\d\d):(\d\d):(\d\d)\s+(\d+)\s+UTC?
        \s+=\s+
        \S+\s+(\S+)\s+(\d+)\s+(\d\d):(\d\d):(\d\d)\s+(\d+)\s+\S+
        \s+isdst=\d+\s+gmtoff=(-?\d+)\n
        \z/x !~ line
      raise "unexpected zdump line: #{line.inspect}"
    end
    tz, u_mon, u_day, u_hour, u_min, u_sec, u_year,
      l_mon, l_day, l_hour, l_min, l_sec, l_year, gmtoff = $~.captures
    u_year = u_year.to_i
    u_mon = MON2NUM[u_mon]
    u_day = u_day.to_i
    u_hour = u_hour.to_i
    u_min = u_min.to_i
    u_sec = u_sec.to_i
    l_year = l_year.to_i
    l_mon = MON2NUM[l_mon]
    l_day = l_day.to_i
    l_hour = l_hour.to_i
    l_min = l_min.to_i
    l_sec = l_sec.to_i
    gmtoff = gmtoff.to_i
    [tz,
     [u_year, u_mon, u_day, u_hour, u_min, u_sec],
     [l_year, l_mon, l_day, l_hour, l_min, l_sec],
     gmtoff]
  end

  def self.gen_zdump_test(data)
    sample = []
    data.each_line {|line|
      s = parse_zdump_line(line)
      sample << s if s
    }
    sample.each {|tz, u, l, gmtoff|
      expected_utc = "%04d-%02d-%02d %02d:%02d:%02d UTC" % u
      expected = "%04d-%02d-%02d %02d:%02d:%02d %s" % (l+[format_gmtoff(gmtoff)])
      mesg_utc = "TZ=#{tz} Time.utc(#{u.map {|arg| arg.inspect }.join(', ')})"
      mesg = "#{mesg_utc}.localtime"
      define_method(gen_test_name(tz)) {
        with_tz(tz) {
          t = nil
          assert_nothing_raised(mesg) { t = Time.utc(*u) }
          assert_equal(expected_utc, time_to_s(t), mesg_utc)
          assert_nothing_raised(mesg) { t.localtime }
          assert_equal(expected, time_to_s(t), mesg)
          assert_equal(gmtoff, t.gmtoff)
          assert_equal(format_gmtoff(gmtoff), t.strftime("%z"))
          assert_equal(format_gmtoff(gmtoff, true), t.strftime("%:z"))
          assert_equal(format_gmtoff2(gmtoff), t.strftime("%::z"))
          assert_equal(Encoding::US_ASCII, t.zone.encoding)
        }
      }
    }

    group_by(sample) {|tz, _, _, _| tz }.each {|tz, a|
      a.each_with_index {|(_, _, l, gmtoff), i|
        expected = "%04d-%02d-%02d %02d:%02d:%02d %s" % (l+[format_gmtoff(gmtoff)])
        monotonic_to_past = i == 0 || (a[i-1][2] <=> l) < 0
        monotonic_to_future = i == a.length-1 || (l <=> a[i+1][2]) < 0
        if monotonic_to_past && monotonic_to_future
          define_method(gen_test_name(tz)) {
            with_tz(tz) {
              assert_time_constructor(tz, expected, :local, l)
              assert_time_constructor(tz, expected, :local, l.reverse+[nil, nil, false, nil])
              assert_time_constructor(tz, expected, :local, l.reverse+[nil, nil, true, nil])
              assert_time_constructor(tz, expected, :new, l)
              assert_time_constructor(tz, expected, :new, l+[:std])
              assert_time_constructor(tz, expected, :new, l+[:dst])
            }
          }
        elsif monotonic_to_past && !monotonic_to_future
          define_method(gen_test_name(tz)) {
            with_tz(tz) {
              assert_time_constructor(tz, expected, :local, l.reverse+[nil, nil, true, nil])
              assert_time_constructor(tz, expected, :new, l+[:dst])
            }
          }
        elsif !monotonic_to_past && monotonic_to_future
          define_method(gen_test_name(tz)) {
            with_tz(tz) {
              assert_time_constructor(tz, expected, :local, l.reverse+[nil, nil, false, nil])
              assert_time_constructor(tz, expected, :new, l+[:std])
            }
          }
        else
          define_method(gen_test_name(tz)) {
            flunk("time in reverse order: TZ=#{tz} #{expected}")
          }
        end
      }
    }
  end

  gen_zdump_test <<'End'
America/Lima  Sun Apr  1 03:59:59 1990 UTC = Sat Mar 31 23:59:59 1990 PEST isdst=1 gmtoff=-14400
America/Lima  Sun Apr  1 04:00:00 1990 UTC = Sat Mar 31 23:00:00 1990 PET isdst=0 gmtoff=-18000
America/Lima  Sat Jan  1 04:59:59 1994 UTC = Fri Dec 31 23:59:59 1993 PET isdst=0 gmtoff=-18000
America/Lima  Sat Jan  1 05:00:00 1994 UTC = Sat Jan  1 01:00:00 1994 PEST isdst=1 gmtoff=-14400
America/Lima  Fri Apr  1 03:59:59 1994 UTC = Thu Mar 31 23:59:59 1994 PEST isdst=1 gmtoff=-14400
America/Lima  Fri Apr  1 04:00:00 1994 UTC = Thu Mar 31 23:00:00 1994 PET isdst=0 gmtoff=-18000
America/Los_Angeles  Sun Apr  2 09:59:59 2006 UTC = Sun Apr  2 01:59:59 2006 PST isdst=0 gmtoff=-28800
America/Los_Angeles  Sun Apr  2 10:00:00 2006 UTC = Sun Apr  2 03:00:00 2006 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Oct 29 08:59:59 2006 UTC = Sun Oct 29 01:59:59 2006 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Oct 29 09:00:00 2006 UTC = Sun Oct 29 01:00:00 2006 PST isdst=0 gmtoff=-28800
America/Los_Angeles  Sun Mar 11 09:59:59 2007 UTC = Sun Mar 11 01:59:59 2007 PST isdst=0 gmtoff=-28800
America/Los_Angeles  Sun Mar 11 10:00:00 2007 UTC = Sun Mar 11 03:00:00 2007 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Nov  4 08:59:59 2007 UTC = Sun Nov  4 01:59:59 2007 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Nov  4 09:00:00 2007 UTC = Sun Nov  4 01:00:00 2007 PST isdst=0 gmtoff=-28800
America/Managua  Thu Sep 24 04:59:59 1992 UTC = Wed Sep 23 23:59:59 1992 EST isdst=0 gmtoff=-18000
America/Managua  Thu Sep 24 05:00:00 1992 UTC = Wed Sep 23 23:00:00 1992 CST isdst=0 gmtoff=-21600
America/Managua  Fri Jan  1 05:59:59 1993 UTC = Thu Dec 31 23:59:59 1992 CST isdst=0 gmtoff=-21600
America/Managua  Fri Jan  1 06:00:00 1993 UTC = Fri Jan  1 01:00:00 1993 EST isdst=0 gmtoff=-18000
America/Managua  Wed Jan  1 04:59:59 1997 UTC = Tue Dec 31 23:59:59 1996 EST isdst=0 gmtoff=-18000
America/Managua  Wed Jan  1 05:00:00 1997 UTC = Tue Dec 31 23:00:00 1996 CST isdst=0 gmtoff=-21600
Asia/Singapore  Sun Aug  8 16:30:00 1965 UTC = Mon Aug  9 00:00:00 1965 SGT isdst=0 gmtoff=27000
Asia/Singapore  Thu Dec 31 16:29:59 1981 UTC = Thu Dec 31 23:59:59 1981 SGT isdst=0 gmtoff=27000
Asia/Singapore  Thu Dec 31 16:30:00 1981 UTC = Fri Jan  1 00:30:00 1982 SGT isdst=0 gmtoff=28800
End
  gen_zdump_test CORRECT_TOKYO_DST_1951 ? <<'End' + (CORRECT_TOKYO_DST_1951 < "2018f" ? <<'2018e' : <<'2018f') : <<'End'
Asia/Tokyo  Sat May  5 14:59:59 1951 UTC = Sat May  5 23:59:59 1951 JST isdst=0 gmtoff=32400
Asia/Tokyo  Sat May  5 15:00:00 1951 UTC = Sun May  6 01:00:00 1951 JDT isdst=1 gmtoff=36000
End
Asia/Tokyo  Sat Sep  8 13:59:59 1951 UTC = Sat Sep  8 23:59:59 1951 JDT isdst=1 gmtoff=36000
Asia/Tokyo  Sat Sep  8 14:00:00 1951 UTC = Sat Sep  8 23:00:00 1951 JST isdst=0 gmtoff=32400
2018e
Asia/Tokyo  Sat Sep  8 14:59:59 1951 UTC = Sun Sep  9 00:59:59 1951 JDT isdst=1 gmtoff=36000
Asia/Tokyo  Sat Sep  8 15:00:00 1951 UTC = Sun Sep  9 00:00:00 1951 JST isdst=0 gmtoff=32400
2018f
Asia/Tokyo  Sat May  5 16:59:59 1951 UTC = Sun May  6 01:59:59 1951 JST isdst=0 gmtoff=32400
Asia/Tokyo  Sat May  5 17:00:00 1951 UTC = Sun May  6 03:00:00 1951 JDT isdst=1 gmtoff=36000
Asia/Tokyo  Fri Sep  7 15:59:59 1951 UTC = Sat Sep  8 01:59:59 1951 JDT isdst=1 gmtoff=36000
Asia/Tokyo  Fri Sep  7 16:00:00 1951 UTC = Sat Sep  8 01:00:00 1951 JST isdst=0 gmtoff=32400
End
  gen_zdump_test <<'End'
America/St_Johns  Sun Mar 11 03:30:59 2007 UTC = Sun Mar 11 00:00:59 2007 NST isdst=0 gmtoff=-12600
America/St_Johns  Sun Mar 11 03:31:00 2007 UTC = Sun Mar 11 01:01:00 2007 NDT isdst=1 gmtoff=-9000
America/St_Johns  Sun Nov  4 02:30:59 2007 UTC = Sun Nov  4 00:00:59 2007 NDT isdst=1 gmtoff=-9000
America/St_Johns  Sun Nov  4 02:31:00 2007 UTC = Sat Nov  3 23:01:00 2007 NST isdst=0 gmtoff=-12600
Europe/Brussels  Sun Apr 30 22:59:59 1916 UTC = Sun Apr 30 23:59:59 1916 CET isdst=0 gmtoff=3600
Europe/Brussels  Sun Apr 30 23:00:00 1916 UTC = Mon May  1 01:00:00 1916 CEST isdst=1 gmtoff=7200
Europe/Brussels  Sat Sep 30 22:59:59 1916 UTC = Sun Oct  1 00:59:59 1916 CEST isdst=1 gmtoff=7200
Europe/Brussels  Sat Sep 30 23:00:00 1916 UTC = Sun Oct  1 00:00:00 1916 CET isdst=0 gmtoff=3600
Europe/London  Sun Mar 16 01:59:59 1947 UTC = Sun Mar 16 01:59:59 1947 GMT isdst=0 gmtoff=0
Europe/London  Sun Mar 16 02:00:00 1947 UTC = Sun Mar 16 03:00:00 1947 BST isdst=1 gmtoff=3600
Europe/London  Sun Apr 13 00:59:59 1947 UTC = Sun Apr 13 01:59:59 1947 BST isdst=1 gmtoff=3600
Europe/London  Sun Apr 13 01:00:00 1947 UTC = Sun Apr 13 03:00:00 1947 BDST isdst=1 gmtoff=7200
Europe/London  Sun Aug 10 00:59:59 1947 UTC = Sun Aug 10 02:59:59 1947 BDST isdst=1 gmtoff=7200
Europe/London  Sun Aug 10 01:00:00 1947 UTC = Sun Aug 10 02:00:00 1947 BST isdst=1 gmtoff=3600
Europe/London  Sun Nov  2 01:59:59 1947 UTC = Sun Nov  2 02:59:59 1947 BST isdst=1 gmtoff=3600
Europe/London  Sun Nov  2 02:00:00 1947 UTC = Sun Nov  2 02:00:00 1947 GMT isdst=0 gmtoff=0
End
  if CORRECT_KIRITIMATI_SKIP_1994
    gen_zdump_test <<'End'
Pacific/Kiritimati  Sat Dec 31 09:59:59 1994 UTC = Fri Dec 30 23:59:59 1994 LINT isdst=0 gmtoff=-36000
Pacific/Kiritimati  Sat Dec 31 10:00:00 1994 UTC = Sun Jan  1 00:00:00 1995 LINT isdst=0 gmtoff=50400
End
  else
    gen_zdump_test <<'End'
Pacific/Kiritimati  Sun Jan  1 09:59:59 1995 UTC = Sat Dec 31 23:59:59 1994 LINT isdst=0 gmtoff=-36000
Pacific/Kiritimati  Sun Jan  1 10:00:00 1995 UTC = Mon Jan  2 00:00:00 1995 LINT isdst=0 gmtoff=50400
End
  end
  gen_zdump_test <<'End' if has_right_tz
right/America/Los_Angeles  Fri Jun 30 23:59:60 1972 UTC = Fri Jun 30 16:59:60 1972 PDT isdst=1 gmtoff=-25200
right/America/Los_Angeles  Wed Dec 31 23:59:60 2008 UTC = Wed Dec 31 15:59:60 2008 PST isdst=0 gmtoff=-28800
#right/Asia/Tokyo  Fri Jun 30 23:59:60 1972 UTC = Sat Jul  1 08:59:60 1972 JST isdst=0 gmtoff=32400
#right/Asia/Tokyo  Sat Dec 31 23:59:60 2005 UTC = Sun Jan  1 08:59:60 2006 JST isdst=0 gmtoff=32400
right/Europe/Paris  Fri Jun 30 23:59:60 1972 UTC = Sat Jul  1 00:59:60 1972 CET isdst=0 gmtoff=3600
right/Europe/Paris  Wed Dec 31 23:59:60 2008 UTC = Thu Jan  1 00:59:60 2009 CET isdst=0 gmtoff=3600
End

  def self.gen_variational_zdump_test(hint, data)
    sample = []
    data.each_line {|line|
      s = parse_zdump_line(line)
      sample << s if s
    }

    define_method(gen_test_name(hint)) {
      results = []
      sample.each {|tz, u, l, gmtoff|
        expected_utc = "%04d-%02d-%02d %02d:%02d:%02d UTC" % u
        expected = "%04d-%02d-%02d %02d:%02d:%02d %s" % (l+[format_gmtoff(gmtoff)])
        mesg_utc = "TZ=#{tz} Time.utc(#{u.map {|arg| arg.inspect }.join(', ')})"
        mesg = "#{mesg_utc}.localtime"
        with_tz(tz) {
          t = nil
          assert_nothing_raised(mesg) { t = Time.utc(*u) }
          assert_equal(expected_utc, time_to_s(t), mesg_utc)
          assert_nothing_raised(mesg) { t.localtime }

          results << [
            expected == time_to_s(t),
            gmtoff == t.gmtoff,
            format_gmtoff(gmtoff) == t.strftime("%z"),
            format_gmtoff(gmtoff, true) == t.strftime("%:z"),
            format_gmtoff2(gmtoff) == t.strftime("%::z")
          ]
        }
      }
      assert_include(results, [true, true, true, true, true])
    }
  end

  # tzdata-2014g fixed the offset for lisbon from -0:36:32 to -0:36:45.
  # [ruby-core:65058] [Bug #10245]
  gen_variational_zdump_test "lisbon", <<'End' if has_lisbon_tz
Europe/Lisbon  Mon Jan  1 00:36:31 1912 UTC = Sun Dec 31 23:59:59 1911 LMT isdst=0 gmtoff=-2192
Europe/Lisbon  Mon Jan  1 00:36:44 1912 UT = Sun Dec 31 23:59:59 1911 LMT isdst=0 gmtoff=-2205
Europe/Lisbon  Sun Dec 31 23:59:59 1911 UT = Sun Dec 31 23:23:14 1911 LMT isdst=0 gmtoff=-2205
End

  class TZ
    attr_reader :name

    def initialize(name, abbr, offset, abbr2 = nil, offset2 = nil)
      @name = name
      @abbr = abbr
      @offset = offset
      @abbr2 = abbr2
      @offset2 = offset2
    end

    def dst?(t)
      return false unless @offset2
      case t when Integer
        return nil
      end
      case t.mon
      when 4..9
        true
      else
        false
      end
    end

    def offset(t)
      (dst?(t) ? @offset2 : @offset)
    end

    def local_to_utc(t)
      t - offset(t)
    end

    def utc_to_local(t)
      t + offset(t)
    end

    def abbr(t)
      dst?(t) ? @abbr2 : @abbr
    end

    def ==(other)
      @name == other.name and abbr(0) == other.abbr(0) and offset(0) == other.offset(0)
    end

    def inspect
      "#<TZ: #@name #@abbr #@offset>"
    end
  end
end

module TestTimeTZ::WithTZ
  def subtest_new(time_class, tz, tzarg, tzname, abbr, utc_offset)
    abbr, abbr2 = *abbr
    utc_offset, utc_offset2 = *utc_offset
    t = time_class.new(2018, 9, 1, 12, 0, 0, tzarg)
    utc_offset, abbr = utc_offset2, abbr2 if tz.dst?(t)
    assert_equal([2018, 9, 1, 12, 0, 0, tz], [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.zone])
    h, m = (-utc_offset / 60).divmod(60)
    assert_equal(time_class.utc(2018, 9, 1, 12+h, m, 0).to_i, t.to_i)
    assert_equal(6, t.wday)
    assert_equal(244, t.yday)
  end

  def subtest_now(time_class, tz, tzarg, tzname, abbr, utc_offset)
    t = time_class.now(in: tzarg)
    assert_equal(tz, t.zone)
  end

  def subtest_getlocal(time_class, tz, tzarg, tzname, abbr, utc_offset)
    abbr, abbr2 = *abbr
    utc_offset, utc_offset2 = *utc_offset
    utc = time_class.utc(2018, 9, 1, 12, 0, 0)
    utc_offset, abbr = utc_offset2, abbr2 if tz.dst?(utc)
    t = utc.getlocal(tzarg)
    h, m = (utc_offset / 60).divmod(60)
    assert_equal([2018, 9, 1, 12+h, m, 0, tz], [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.zone])
    assert_equal(time_class.utc(2018, 9, 1, 12, 0, 0), t)
  end

  def subtest_strftime(time_class, tz, tzarg, tzname, abbr, utc_offset)
    abbr, abbr2 = *abbr
    utc_offset, utc_offset2 = *utc_offset
    t = time_class.new(2018, 9, 1, 12, 0, 0, tzarg)
    utc_offset, abbr = utc_offset2, abbr2 if tz.dst?(t)
    h, m = (utc_offset.abs / 60).divmod(60)
    h = -h if utc_offset < 0
    assert_equal("%+.2d%.2d %s" % [h, m, abbr], t.strftime("%z %Z"))
    assert_equal("34 35 35", t.strftime("%U %V %W"))
  end

  def subtest_plus(time_class, tz, tzarg, tzname, abbr, utc_offset)
    abbr, abbr2 = *abbr
    utc_offset, utc_offset2 = *utc_offset
    t = time_class.new(2018, 9, 1, 12, 0, 0, tzarg) + 4000
    utc_offset, abbr = utc_offset2, abbr2 if tz.dst?(t)
    assert_equal([2018, 9, 1, 13, 6, 40, tz], [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.zone])
    m, s = (4000-utc_offset).divmod(60)
    h, m = m.divmod(60)
    assert_equal(time_class.utc(2018, 9, 1, 12+h, m, s), t)
  end

  def subtest_at(time_class, tz, tzarg, tzname, abbr, utc_offset)
    abbr, abbr2 = *abbr
    utc_offset, utc_offset2 = *utc_offset
    utc = time_class.utc(2018, 9, 1, 12, 0, 0)
    utc_offset, abbr = utc_offset2, abbr2 if tz.dst?(utc)
    h, m = (utc_offset / 60).divmod(60)
    t = time_class.at(utc, in: tzarg)
    assert_equal([2018, 9, 1, 12+h, m, 0, tz], [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.zone])
    assert_equal(utc.to_i, t.to_i)
    utc = utc.to_i
    t = time_class.at(utc, in: tzarg)
    assert_equal([2018, 9, 1, 12+h, m, 0, tz], [t.year, t.mon, t.mday, t.hour, t.min, t.sec, t.zone])
    assert_equal(utc, t.to_i)
  end

  def subtest_marshal(time_class, tz, tzarg, tzname, abbr, utc_offset)
    t = time_class.new(2018, 9, 1, 12, 0, 0, tzarg)
    t2 = Marshal.load(Marshal.dump(t))
    assert_equal(t, t2)
    assert_equal(t.utc_offset, t2.utc_offset)
    assert_equal(t.utc_offset, (t2+1).utc_offset)
    assert_instance_of(t.zone.class, t2.zone)
    assert_equal(t.dst?, t2.dst?)
  end

  def test_invalid_zone
    make_timezone("INVALID", "INV", 0)
  rescue => e
    assert_kind_of(StandardError, e)
  else
    assert false, "ArgumentError expected but nothing was raised."
  end

  def nametest_marshal_compatibility(time_class, tzname, abbr, utc_offset)
    data = [
      "\x04\x08Iu:".b, Marshal.dump(time_class)[3..-1],
      "\x0d""\xEF\xA7\x1D\x80\x00\x00\x00\x00".b,
      Marshal.dump({offset: utc_offset, zone: abbr})[3..-1],
    ].join('')
    t = Marshal.load(data)
    assert_equal(utc_offset, t.utc_offset)
    assert_equal(utc_offset, (t+1).utc_offset)
    # t.zone may be a mere String or timezone object.
  end

  ZONES = {
    "Asia/Tokyo" => ["JST", +9*3600],
    "America/Los_Angeles" => ["PST", -8*3600, "PDT", -7*3600],
    "Africa/Ndjamena" => ["WAT", +1*3600],
  }

  def make_timezone(tzname, abbr, utc_offset, abbr2 = nil, utc_offset2 = nil)
    self.class::TIME_CLASS.find_timezone(tzname)
  end

  def subtest_dst?(time_class, tz, tzarg, tzname, abbr, utc_offset)
    t = time_class.new(2018, 6, 22, 12, 0, 0, tzarg)
    return unless tz.dst?(t)
    assert_predicate t, :dst?
    t = time_class.new(2018, 12, 22, 12, 0, 0, tzarg)
    assert_not_predicate t, :dst?
  end

  instance_methods(false).grep(/\Asub(?=test_)/) do |subtest|
    test = $'
    ZONES.each_pair do |tzname, (abbr, utc_offset, abbr2, utc_offset2)|
      define_method("#{test}@#{tzname}") do
        tz = make_timezone(tzname, abbr, utc_offset, abbr2, utc_offset2)
        time_class = self.class::TIME_CLASS
        __send__(subtest, time_class, tz, tz, tzname, [abbr, abbr2], [utc_offset, utc_offset2])
        __send__(subtest, time_class, tz, tzname, tzname, [abbr, abbr2], [utc_offset, utc_offset2])
      end
    end
  end

  instance_methods(false).grep(/\Aname(?=test_)/) do |subtest|
    test = $'
    ZONES.each_pair do |tzname, (abbr, utc_offset)|
      define_method("#{test}@#{tzname}") do
        time_class = self.class::TIME_CLASS
        __send__(subtest, time_class, tzname, abbr, utc_offset)
      end
    end
  end
end

class TestTimeTZ::DummyTZ < Test::Unit::TestCase
  include TestTimeTZ::WithTZ

  class TIME_CLASS < ::Time
    ZONES = TestTimeTZ::WithTZ::ZONES
    def self.find_timezone(tzname)
      tz = ZONES[tzname] or raise ArgumentError, "Unknown timezone: #{name}"
      TestTimeTZ::TZ.new(tzname, *tz)
    end
  end

  def self.make_timezone(tzname, abbr, utc_offset, abbr2 = nil, utc_offset2 = nil)
    TestTimeTZ::TZ.new(tzname, abbr, utc_offset, abbr2, utc_offset2)
  end
end

begin
  require "tzinfo"
rescue LoadError
else
  class TestTimeTZ::GemTZInfo < Test::Unit::TestCase
    include TestTimeTZ::WithTZ

    class TIME_CLASS < ::Time
      def self.find_timezone(tzname)
        TZInfo::Timezone.get(tzname)
      end
    end

    def tz
      @tz ||= TZInfo::Timezone.get(tzname)
    end
  end
end

begin
  require "timezone"
rescue LoadError
else
  class TestTimeTZ::GemTimezone < Test::Unit::TestCase
    include TestTimeTZ::WithTZ

    class TIME_CLASS < ::Time
      def self.find_timezone(name)
        Timezone.fetch(name)
      end
    end

    def tz
      @tz ||= Timezone[tzname]
    end
  end
end
