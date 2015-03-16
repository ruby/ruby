require 'minitest/autorun'
require 'stringio'
require 'tempfile'
require 'date'
require 'psych'

module Psych
  superclass = if defined?(Minitest::Test)
                 Minitest::Test
               else
                 MiniTest::Unit::TestCase
               end

  class TestCase < superclass
    def self.suppress_warning
      verbose, $VERBOSE = $VERBOSE, nil
      yield
    ensure
      $VERBOSE = verbose
    end

    def with_default_external(enc)
      verbose, $VERBOSE = $VERBOSE, nil
      origenc, Encoding.default_external = Encoding.default_external, enc
      $VERBOSE = verbose
      yield
    ensure
      verbose, $VERBOSE = $VERBOSE, nil
      Encoding.default_external = origenc
      $VERBOSE = verbose
    end

    def with_default_internal(enc)
      verbose, $VERBOSE = $VERBOSE, nil
      origenc, Encoding.default_internal = Encoding.default_internal, enc
      $VERBOSE = verbose
      yield
    ensure
      verbose, $VERBOSE = $VERBOSE, nil
      Encoding.default_internal = origenc
      $VERBOSE = verbose
    end

    #
    # Convert between Psych and the object to verify correct parsing and
    # emitting
    #
    def assert_to_yaml( obj, yaml )
      assert_equal( obj, Psych::load( yaml ) )
      assert_equal( obj, Psych::parse( yaml ).transform )
      assert_equal( obj, Psych::load( obj.psych_to_yaml ) )
      assert_equal( obj, Psych::parse( obj.psych_to_yaml ).transform )
      assert_equal( obj, Psych::load(
        obj.psych_to_yaml(
          :UseVersion => true, :UseHeader => true, :SortKeys => true
        )
      ))
    end

    #
    # Test parser only
    #
    def assert_parse_only( obj, yaml )
      assert_equal( obj, Psych::load( yaml ) )
      assert_equal( obj, Psych::parse( yaml ).transform )
    end

    def assert_cycle( obj )
      v = Visitors::YAMLTree.create
      v << obj
      assert_equal(obj, Psych.load(v.tree.yaml))
      assert_equal( obj, Psych::load(Psych.dump(obj)))
      assert_equal( obj, Psych::load( obj.psych_to_yaml ) )
    end

    #
    # Make a time with the time zone
    #
    def mktime( year, mon, day, hour, min, sec, usec, zone = "Z" )
      usec = Rational(usec.to_s) * 1000000
      val = Time::utc( year.to_i, mon.to_i, day.to_i, hour.to_i, min.to_i, sec.to_i, usec )
      if zone != "Z"
        hour = zone[0,3].to_i * 3600
        min = zone[3,2].to_i * 60
        ofs = (hour + min)
        val = Time.at( val.tv_sec - ofs, val.tv_nsec / 1000.0 )
      end
      return val
    end
  end
end

# backport so that tests will run on 1.9 and 2.0.0
unless Tempfile.respond_to? :create
  def Tempfile.create(basename, *rest)
    tmpfile = nil
    Dir::Tmpname.create(basename, *rest) do |tmpname, n, opts|
      mode = File::RDWR|File::CREAT|File::EXCL
      perm = 0600
      if opts
        mode |= opts.delete(:mode) || 0
        opts[:perm] = perm
        perm = nil
      else
        opts = perm
      end
      tmpfile = File.open(tmpname, mode, opts)
    end
    if block_given?
      begin
        yield tmpfile
      ensure
        tmpfile.close if !tmpfile.closed?
        File.unlink tmpfile
      end
    else
      tmpfile
    end
  end
end
