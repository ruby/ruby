require 'test/unit'

class TestTimeTZ < Test::Unit::TestCase
  def with_tz(tz)
    if /linux/ =~ RUBY_PLATFORM || ENV["RUBY_TEST_TIME_TZ"] == "yes"
      old = ENV["TZ"]
      begin
        ENV["TZ"] = tz
        yield
      ensure
        ENV["TZ"] = old
      end
    else
      if ENV["TZ"] == tz
        yield
      end
    end
  end

  def test_asia_tokyo
    with_tz("Asia/Tokyo") {
      assert_equal("2010-10-06 06:13:28 +0900", Time.local(2010,10,6,6,13,28).to_s)
    }
  end

  def test_europe_brussels
    with_tz("Europe/Brussels") {
      assert_equal("1916-04-30 23:59:59 +0100", Time.local(1916,4,30,23,59,59).to_s)
      assert_equal("1916-05-01 01:00:00 +0200", Time.local(1916,5,1).to_s, "[ruby-core:30672]")
      assert_equal("1916-05-01 01:59:59 +0200", Time.local(1916,5,1,0,59,59).to_s)
      assert_equal("1916-05-01 01:00:00 +0200", Time.local(1916,5,1,1,0,0).to_s)
      assert_equal("1916-05-01 01:59:59 +0200", Time.local(1916,5,1,1,59,59).to_s)
    }
  end

  def test_europe_moscow
    with_tz("Europe/Moscow") {
      assert_equal("1992-03-29 00:00:00 +0400", Time.local(1992,3,28,23,0,0).to_s)
      assert_equal("1992-03-29 00:59:59 +0400", Time.local(1992,3,28,23,59,59).to_s)
    }
  end

  def test_pacific_kiritimati
    with_tz("Pacific/Kiritimati") {
      assert_equal("1994-12-31 23:59:59 -1000", Time.local(1994,12,31,23,59,59).to_s)
      assert_equal("1995-01-02 00:00:00 +1400", Time.local(1995,1,1,0,0,0).to_s)
      assert_equal("1995-01-02 23:59:59 +1400", Time.local(1995,1,1,23,59,59).to_s)
      assert_equal("1995-01-02 00:00:00 +1400", Time.local(1995,1,2,0,0,0).to_s)
    }
  end

  def test_america_los_angeles
    with_tz("America/Los_Angeles") {
      assert_equal("2007-03-11 03:00:00 -0700", Time.local(2007,3,11,2,0,0).to_s)
      assert_equal("2007-03-11 03:59:59 -0700", Time.local(2007,3,11,2,59,59).to_s)
    }
  end

  MON2NUM = {
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  def check_zdump(zdump_result)
    zdump_result.each_line {|line|
      /\A(?<tz>\S+)\s+
       \S+\s+(?<u_mon>\S+)\s+(?<u_day>\d+)\s+(?<u_hour>\d\d):(?<u_min>\d\d):(?<u_sec>\d\d)\s+(?<u_year>\d+)\s+UTC\s+=\s+
       \S+\s+(?<l_mon>\S+)\s+(?<l_day>\d+)\s+(?<l_hour>\d\d):(?<l_min>\d\d):(?<l_sec>\d\d)\s+(?<l_year>\d+)\s+\S+\s+isdst=\d+\s+gmtoff=(?<l_gmtoff>-?\d+)\n
       \z/x =~ line
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
      l_gmtoff = l_gmtoff.to_i
      with_tz(tz) {
        expected = "%04d-%02d-%02d %02d:%02d:%02d " % [l_year, l_mon, l_day, l_hour, l_min, l_sec]
        if l_gmtoff < 0
          expected << "-"
          l_gmtoff = -l_gmtoff
        else
          expected << "+"
        end
        l_gmtoff /= 60
        expected << "%02d%02d" % [l_gmtoff / 60, l_gmtoff % 60]
        assert_equal(expected, Time.utc(u_year, u_mon, u_day, u_hour, u_min, u_sec).localtime.to_s)
      }
    }
  end

  def test_zdump
    check_zdump <<'End'
Asia/Tokyo  Sat May  5 16:59:59 1951 UTC = Sun May  6 01:59:59 1951 JST isdst=0 gmtoff=32400
Asia/Tokyo  Sat May  5 17:00:00 1951 UTC = Sun May  6 03:00:00 1951 JDT isdst=1 gmtoff=36000
Asia/Tokyo  Fri Sep  7 15:59:59 1951 UTC = Sat Sep  8 01:59:59 1951 JDT isdst=1 gmtoff=36000
Asia/Tokyo  Fri Sep  7 16:00:00 1951 UTC = Sat Sep  8 01:00:00 1951 JST isdst=0 gmtoff=32400
Europe/Brussels  Sun Apr 30 22:59:59 1916 UTC = Sun Apr 30 23:59:59 1916 CET isdst=0 gmtoff=3600
Europe/Brussels  Sun Apr 30 23:00:00 1916 UTC = Mon May  1 01:00:00 1916 CEST isdst=1 gmtoff=7200
Europe/Brussels  Sat Sep 30 22:59:59 1916 UTC = Sun Oct  1 00:59:59 1916 CEST isdst=1 gmtoff=7200
Europe/Brussels  Sat Sep 30 23:00:00 1916 UTC = Sun Oct  1 00:00:00 1916 CET isdst=0 gmtoff=3600
Europe/Moscow  Sat Jan 18 23:59:59 1992 UTC = Sun Jan 19 01:59:59 1992 MSK isdst=0 gmtoff=7200
Europe/Moscow  Sun Jan 19 00:00:00 1992 UTC = Sun Jan 19 03:00:00 1992 MSK isdst=0 gmtoff=10800
Europe/Moscow  Sat Mar 28 19:59:59 1992 UTC = Sat Mar 28 22:59:59 1992 MSK isdst=0 gmtoff=10800
Europe/Moscow  Sat Mar 28 20:00:00 1992 UTC = Sun Mar 29 00:00:00 1992 MSD isdst=1 gmtoff=14400
Europe/Moscow  Sat Sep 26 18:59:59 1992 UTC = Sat Sep 26 22:59:59 1992 MSD isdst=1 gmtoff=14400
Europe/Moscow  Sat Sep 26 19:00:00 1992 UTC = Sat Sep 26 22:00:00 1992 MSK isdst=0 gmtoff=10800
Pacific/Kiritimati  Sun Jan  1 09:59:59 1995 UTC = Sat Dec 31 23:59:59 1994 LINT isdst=0 gmtoff=-36000
Pacific/Kiritimati  Sun Jan  1 10:00:00 1995 UTC = Mon Jan  2 00:00:00 1995 LINT isdst=0 gmtoff=50400
America/Los_Angeles  Sun Apr  2 09:59:59 2006 UTC = Sun Apr  2 01:59:59 2006 PST isdst=0 gmtoff=-28800
America/Los_Angeles  Sun Apr  2 10:00:00 2006 UTC = Sun Apr  2 03:00:00 2006 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Oct 29 08:59:59 2006 UTC = Sun Oct 29 01:59:59 2006 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Oct 29 09:00:00 2006 UTC = Sun Oct 29 01:00:00 2006 PST isdst=0 gmtoff=-28800
America/Los_Angeles  Sun Mar 11 09:59:59 2007 UTC = Sun Mar 11 01:59:59 2007 PST isdst=0 gmtoff=-28800
America/Los_Angeles  Sun Mar 11 10:00:00 2007 UTC = Sun Mar 11 03:00:00 2007 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Nov  4 08:59:59 2007 UTC = Sun Nov  4 01:59:59 2007 PDT isdst=1 gmtoff=-25200
America/Los_Angeles  Sun Nov  4 09:00:00 2007 UTC = Sun Nov  4 01:00:00 2007 PST isdst=0 gmtoff=-28800
End
  end
end
