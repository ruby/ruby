require 'test/unit'
require 'tempfile'
require 'fileutils'

require 'csv'

class CSV
  class StreamBuf
    # Let buffer work hard.
    remove_const("BufSize")
    BufSize = 2
  end
end


module CSVTestSupport
  def d(data)
    data
  end
end


class TestCSV < Test::Unit::TestCase
  file = Tempfile.new("crlf")
  file << "\n"
  file.open
  file.binmode
  RSEP = file.read
  file.close

  include CSVTestSupport

  class << self
    include CSVTestSupport
  end

  @@simpleCSVData = {
    [nil] => '',
    [''] => '""',
    [nil, nil] => ',',
    [nil, nil, nil] => ',,',
    ['foo'] => 'foo',
    [','] => '","',
    [',', ','] => '",",","',
    [';'] => ';',
    [';', ';'] => ';,;',
    ["\"\r", "\"\r"] => "\"\"\"\r\",\"\"\"\r\"",
    ["\"\n", "\"\n"] => "\"\"\"\n\",\"\"\"\n\"",
    ["\t"] => "\t",
    ["\t", "\t"] => "\t,\t",
    ['foo', 'bar'] => 'foo,bar',
    ['foo', '"bar"', 'baz'] => 'foo,"""bar""",baz',
    ['foo', 'foo,bar', 'baz'] => 'foo,"foo,bar",baz',
    ['foo', '""', 'baz'] => 'foo,"""""",baz',
    ['foo', '', 'baz'] => 'foo,"",baz',
    ['foo', nil, 'baz'] => 'foo,,baz',
    [nil, 'foo', 'bar'] => ',foo,bar',
    ['foo', 'bar', nil] => 'foo,bar,',
    ['foo', "\r", 'baz'] => "foo,\"\r\",baz",
    ['foo', "\n", 'baz'] => "foo,\"\n\",baz",
    ['foo', "\r\n\r", 'baz'] => "foo,\"\r\n\r\",baz",
    ['foo', "\r\n", 'baz'] => "foo,\"\r\n\",baz",
    ['foo', "\r.\n", 'baz'] => "foo,\"\r.\n\",baz",
    ['foo', "\r\n\n", 'baz'] => "foo,\"\r\n\n\",baz",
    ['foo', '"', 'baz'] => 'foo,"""",baz',
  }

  @@fullCSVData = {
    [d(nil)] => '',
    [d('')] => '""',
    [d(nil), d(nil)] => ',',
    [d(nil), d(nil), d(nil)] => ',,',
    [d('foo')] => 'foo',
    [d('foo'), d('bar')] => 'foo,bar',
    [d('foo'), d('"bar"'), d('baz')] => 'foo,"""bar""",baz',
    [d('foo'), d('foo,bar'), d('baz')] => 'foo,"foo,bar",baz',
    [d('foo'), d('""'), d('baz')] => 'foo,"""""",baz',
    [d('foo'), d(''), d('baz')] => 'foo,"",baz',
    [d('foo'), d(nil), d('baz')] => 'foo,,baz',
    [d('foo'), d("\r"), d('baz')] => "foo,\"\r\",baz",
    [d('foo'), d("\n"), d('baz')] => "foo,\"\n\",baz",
    [d('foo'), d("\r\n"), d('baz')] => "foo,\"\r\n\",baz",
    [d('foo'), d("\r.\n"), d('baz')] => "foo,\"\r.\n\",baz",
    [d('foo'), d("\r\n\n"), d('baz')] => "foo,\"\r\n\n\",baz",
    [d('foo'), d('"'), d('baz')] => 'foo,"""",baz',
  }

  @@fullCSVDataArray = @@fullCSVData.collect { |key, value| key }

  def ssv2csv(ssvStr, row_sep = nil)
    sepConv(ssvStr, ?;, ?,, row_sep)
  end

  def csv2ssv(csvStr, row_sep = nil)
    sepConv(csvStr, ?,, ?;, row_sep)
  end

  def tsv2csv(tsvStr, row_sep = nil)
    sepConv(tsvStr, ?\t, ?,, row_sep)
  end

  def csv2tsv(csvStr, row_sep = nil)
    sepConv(csvStr, ?,, ?\t, row_sep)
  end

  def sepConv(srcStr, srcSep, destSep, row_sep = nil)
    rows = []
    cols, idx = CSV.parse_row(srcStr, 0, rows, srcSep, row_sep)
    destStr = ''
    cols = CSV.generate_row(rows, rows.size, destStr, destSep, row_sep)
    destStr
  end

public

  def setup
    @tmpdir = File.join(Dir.tmpdir, "ruby_test_csv_tmp_#{$$}")
    Dir.mkdir(@tmpdir)
    @infile = File.join(@tmpdir, 'in.csv')
    @infiletsv = File.join(@tmpdir, 'in.tsv')
    @emptyfile = File.join(@tmpdir, 'empty.csv')
    @outfile = File.join(@tmpdir, 'out.csv')
    @bomfile = File.join(@tmpdir, "bom.csv")
    @macfile = File.join(@tmpdir, "mac.csv")

    CSV.open(@infile, "wb") do |writer|
      @@fullCSVDataArray.each do |row|
	writer.add_row(row)
      end
    end

    CSV.open(@infiletsv, "wb", ?\t) do |writer|
      @@fullCSVDataArray.each do |row|
	writer.add_row(row)
      end
    end

    CSV.generate(@emptyfile) do |writer|
      # Create empty file.
    end

    File.open(@bomfile, "wb") do |f|
      f.write("\357\273\277\"foo\"\r\n\"bar\"\r\n")
    end

    File.open(@macfile, "wb") do |f|
      f.write("\"Avenches\",\"aus Umgebung\"\r\"Bad Hersfeld\",\"Ausgrabung\"")
    end
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  #### CSV::Reader unit test
  
  def test_Reader_each
    file = File.open(@infile, "rb")
    begin
      reader = CSV::Reader.create(file)
      expectedArray = @@fullCSVDataArray.dup
      first = true
      ret = reader.each { |row|
	if first
	  assert_instance_of(Array, row)
	  first = false
	end
	expected = expectedArray.shift
	assert_equal(expected, row)
      }
      assert_nil(ret, "Return is nil")
      assert(expectedArray.empty?)
    ensure
      file.close
    end

    # Illegal format.
    reader = CSV::Reader.create("a,b\r\na,b,\"c\"\ra")
    assert_raises(CSV::IllegalFormatError) do
      reader.each do |row|
      end
    end

    reader = CSV::Reader.create("a,b\r\n\"")
    assert_raises(CSV::IllegalFormatError) do
      reader.each do |row|
      end
    end
  end

  def test_Reader_shift
    file = File.open(@infile, "rb")
    begin
      reader = CSV::Reader.create(file)
      first = true
      checked = 0
      @@fullCSVDataArray.each do |expected|
	actual = reader.shift
	if first
	  assert_instance_of(Array, actual)
	  first = false
	end
	assert_equal(expected, actual)
	checked += 1
      end
      assert(checked == @@fullCSVDataArray.size)
    ensure
      file.close
    end

    # Illegal format.
    reader = CSV::Reader.create("a,b\r\na,b,\"c\"\ra")
    assert_raises(CSV::IllegalFormatError) do
      reader.shift
      reader.shift
    end

    reader = CSV::Reader.create("a,b\r\na,b,\"c\"\ra")
    assert_raises(CSV::IllegalFormatError) do
      reader.shift
      reader.shift
    end
  end

  def test_Reader_getRow
    if CSV::Reader.respond_to?(:allocate)
      obj = CSV::Reader.allocate
      assert_raises(NotImplementedError) do
	row = []
	obj.shift
      end
    end
  end

  def test_IOReader_close_on_terminate
    f = File.open(@infile, "r")
    reader = CSV::IOReader.create(f)
    reader.close
    assert(!f.closed?)
    f.close

    f = File.open(@infile, "r")
    writer = CSV::IOReader.create(f)
    writer.close_on_terminate
    writer.close
    assert(f.closed?)
  end

  def test_Reader_close
    f = File.open(@infile, "r")
    reader = CSV::IOReader.create(f)
    reader.close_on_terminate
    reader.close
    assert(f.closed?)
  end

  def test_Reader_s_new
    assert_raises(RuntimeError) do
      CSV::Reader.new(nil)
    end
  end

  def test_Reader_s_create
    reader = CSV::Reader.create("abc")
    assert_instance_of(CSV::StringReader, reader, "With a String")

    file = File.open(@infile, "rb")
    reader = CSV::Reader.create(file)
    assert_instance_of(CSV::IOReader, reader, 'With an IO')

    obj = Object.new
    def obj.sysread(size)
      "abc"
    end
    def obj.read(size)
      "abc"
    end
    reader = CSV::Reader.create(obj)
    assert_instance_of(CSV::IOReader, reader, "With not an IO or String")

    # No need to test Tempfile because it's a pseudo IO.  I test this here
    # fors other tests.
    reader = CSV::Reader.create(Tempfile.new("in.csv"))
    assert_instance_of(CSV::IOReader, reader, "With an pseudo IO.")
    file.close
  end

  def test_IOReader_s_create_binmode
    file = File.open(@outfile, "wb")
    file << "\"\r\n\",\"\r\",\"\n\"\r1,2,3"
    file.close

    file = File.open(@outfile, "rb")
    begin
      reader = CSV::IOReader.new(file, ?,, ?\r)
      assert_equal(["\r\n", "\r", "\n"], reader.shift.to_a)
      assert_equal(["1", "2", "3"], reader.shift.to_a)
      reader.close
    ensure
      file.close
    end

    file = File.open(@outfile, "r")	# not "rb"
    begin
      lfincell = (RSEP == "\n" ? "\r\n" : "\n")
      reader = CSV::IOReader.new(file, ?,, ?\r)
      assert_equal([lfincell, "\r", "\n"], reader.shift.to_a)
      assert_equal(["1", "2", "3"], reader.shift.to_a)
      reader.close
    ensure
      file.close
    end
  end

  def test_Reader_s_parse
    ret = CSV::Reader.parse("a,b,c") { |row|
      assert_instance_of(Array, row, "Block parameter")
    }
    assert_nil(ret, "Return is nil")

    ret = CSV::Reader.parse("a;b;c", ?;) { |row|
      assert_instance_of(Array, row, "Block parameter")
    }

    file = Tempfile.new("in.csv")
    file << "a,b,c"
    file.open
    ret = CSV::Reader.parse(file) { |row|
      assert_instance_of(Array, row, "Block parameter")
    }
    assert_nil(ret, "Return is nil")

    file = Tempfile.new("in.csv")
    file << "a,b,c"
    file.open
    ret = CSV::Reader.parse(file, ?,) { |row|
      assert_instance_of(Array, row, "Block parameter")
    }

    # Illegal format.
    assert_raises(CSV::IllegalFormatError) do
      CSV::Reader.parse("a,b\r\na,b,\"c\"\ra") do |row|
      end
    end

    assert_raises(CSV::IllegalFormatError) do
      CSV::Reader.parse("a,b\r\na,b\"") do |row|
      end
    end
  end


  #### CSV::Writer unit test
  
  def test_Writer_s_new
    assert_raises(RuntimeError) do
      CSV::Writer.new(nil)
    end
  end

  def test_Writer_s_generate
    ret = CSV::Writer.generate(STDOUT) { |writer|
      assert_instance_of(CSV::BasicWriter, writer, "Block parameter")
    }

    ret = CSV::Writer.generate(STDOUT, ?;) { |writer|
      assert_instance_of(CSV::BasicWriter, writer, "Block parameter")
    }

    assert_nil(ret, "Return is nil")
  end

  def test_Writer_s_create
    writer = CSV::Writer.create(STDERR)
    assert_instance_of(CSV::BasicWriter, writer, "String")

    writer = CSV::Writer.create(STDERR, ?;)
    assert_instance_of(CSV::BasicWriter, writer, "String")

    writer = CSV::Writer.create(Tempfile.new("out.csv"))
    assert_instance_of(CSV::BasicWriter, writer, "IO")
  end

  def test_Writer_LSHIFT # '<<'
    file = Tempfile.new("out.csv")
    CSV::Writer.generate(file) do |writer|
      ret = writer << ['a', 'b', 'c']
      assert_instance_of(CSV::BasicWriter, ret, 'Return is self')

      writer << [nil, 'e', 'f'] << [nil, nil, '']
    end
    file.open
    file.binmode
    str = file.read
    assert_equal("a,b,c#{RSEP},e,f#{RSEP},,\"\"#{RSEP}", str, 'Normal')

    file = Tempfile.new("out2.csv")
    CSV::Writer.generate(file) do |writer|
      ret = writer << [d('a'), d('b'), d('c')]
      assert_instance_of(CSV::BasicWriter, ret, 'Return is self')

      writer << [d(nil), d('e'), d('f')] << [d(nil), d(nil), d('')]
    end
    file.open
    file.binmode
    str = file.read
    assert_equal("a,b,c#{RSEP},e,f#{RSEP},,\"\"#{RSEP}", str, 'Normal')
  end

  def test_Writer_add_row
    file = Tempfile.new("out.csv")
    CSV::Writer.generate(file) do |writer|
      ret = writer.add_row(
	[d('a'), d('b'), d('c')])
      assert_instance_of(CSV::BasicWriter, ret, 'Return is self')

      writer.add_row(
	[d(nil), d('e'), d('f')]
     ).add_row(
	[d(nil), d(nil), d('')]
     )
    end
    file.open
    file.binmode
    str = file.read
    assert_equal("a,b,c#{RSEP},e,f#{RSEP},,\"\"#{RSEP}", str, 'Normal')
  end

  def test_Writer_close
    f = File.open(@outfile, "w")
    writer = CSV::BasicWriter.create(f)
    writer.close_on_terminate
    writer.close
    assert(f.closed?)
  end

  def test_BasicWriter_close_on_terminate
    f = File.open(@outfile, "w")
    writer = CSV::BasicWriter.create(f)
    writer.close
    assert(!f.closed?)
    f.close

    f = File.open(@outfile, "w")
    writer = CSV::BasicWriter.new(f)
    writer.close_on_terminate
    writer.close
    assert(f.closed?)
  end

  def test_BasicWriter_s_create_binmode
    file = File.open(@outfile, "w")	# not "wb"
    begin
      writer = CSV::BasicWriter.new(file, ?,, ?\r)
      writer << ["\r\n", "\r", "\n"]
      writer << ["1", "2", "3"]
      writer.close
    ensure
      file.close
    end

    file = File.open(@outfile, "rb")
    str = file.read
    file.close
    assert_equal("\"\r#{RSEP}\",\"\r\",\"#{RSEP}\"\r1,2,3\r", str)
  end

  #### CSV unit test

  def test_s_open_reader
    assert_raises(ArgumentError, 'Illegal mode') do
      CSV.open("temp", "a")
    end

    assert_raises(ArgumentError, 'Illegal mode') do
      CSV.open("temp", "a", ?;)
    end

    reader = CSV.open(@infile, "r")
    assert_instance_of(CSV::IOReader, reader)
    reader.close

    reader = CSV.open(@infile, "rb")
    assert_instance_of(CSV::IOReader, reader)
    reader.close

    reader = CSV.open(@infile, "r", ?;)
    assert_instance_of(CSV::IOReader, reader)
    reader.close

    CSV.open(@infile, "r") do |row|
      assert_instance_of(Array, row)
      break
    end

    CSV.open(@infiletsv, "r", ?\t) do |row|
      assert_instance_of(Array, row)
      break
    end

    assert_raises(Errno::ENOENT) do
      CSV.open("NoSuchFileOrDirectory", "r")
    end

    assert_raises(Errno::ENOENT) do
      CSV.open("NoSuchFileOrDirectory", "r", ?;)
    end

    # Illegal format.
    File.open(@outfile, "wb") do |f|
      f << "a,b\r\na,b,\"c\"\ra"
    end
    assert_raises(CSV::IllegalFormatError) do
      CSV.open(@outfile, "r") do |row|
      end
    end

    File.open(@outfile, "wb") do |f|
      f << "a,b\r\na,b\""
    end
    assert_raises(CSV::IllegalFormatError) do
      CSV.open(@outfile, "r") do |row|
      end
    end

    CSV.open(@emptyfile, "r") do |row|
      assert_fail("Must not reach here")
    end
  end

  def test_s_parse
    result = CSV.parse(File.read(@infile))
    assert_instance_of(Array, result)
    assert_instance_of(Array, result[0])

    result = CSV.parse(File.read(@infile))
    assert_instance_of(Array, result)
    assert_instance_of(Array, result[0])

    assert_equal([], CSV.parse(""))
    assert_equal([[nil]], CSV.parse("\n"))

    CSV.parse(File.read(@infile)) do |row|
      assert_instance_of(Array, row)
      break
    end

    CSV.parse(File.read(@infiletsv), ?\t) do |row|
      assert_instance_of(Array, row)
      break
    end

    CSV.parse("") do |row|
      assert(false)
    end

    count = 0
    CSV.parse("\n") do |row|
      assert_equal([nil], row)
      count += 1
    end
    assert_equal(1, count)

    assert_equal([["a|b-c|d"]], CSV.parse("a|b-c|d"))
    assert_equal([["a", "b"], ["c", "d"]], CSV.parse("a|b-c|d", "|", "-"))
  end

  def test_s_open_writer
    writer = CSV.open(@outfile, "w")
    assert_instance_of(CSV::BasicWriter, writer)
    writer.close

    writer = CSV.open(@outfile, "wb")
    assert_instance_of(CSV::BasicWriter, writer)
    writer.close

    writer = CSV.open(@outfile, "wb", ?;)
    assert_instance_of(CSV::BasicWriter, writer)
    writer.close

    CSV.open(@outfile, "w") do |writer|
      assert_instance_of(CSV::BasicWriter, writer)
    end

    CSV.open(@outfile, "w", ?;) do |writer|
      assert_instance_of(CSV::BasicWriter, writer)
    end

    begin
      CSV.open(@tmpdir, "w")
      assert(false)
    rescue Exception => ex
      assert(ex.is_a?(Errno::EEXIST) || ex.is_a?(Errno::EISDIR) || ex.is_a?(Errno::EACCES))
    end
  end

  def test_s_generate
    writer = CSV.generate(@outfile)
    assert_instance_of(CSV::BasicWriter, writer)
    writer.close

    writer = CSV.generate(@outfile, ?;)
    assert_instance_of(CSV::BasicWriter, writer)
    writer.close

    CSV.generate(@outfile) do |writer|
      assert_instance_of(CSV::BasicWriter, writer)
    end

    CSV.generate(@outfile, ?;) do |writer|
      assert_instance_of(CSV::BasicWriter, writer)
    end

    begin
      CSV.generate(@tmpdir)
      assert(false)
    rescue Exception => ex
      assert(ex.is_a?(Errno::EEXIST) || ex.is_a?(Errno::EISDIR) || ex.is_a?(Errno::EACCES))
    end
  end

  def test_s_generate_line
    str = CSV.generate_line([])
    assert_equal('', str, "Extra boundary check.")

    str = CSV.generate_line([], ?;)
    assert_equal('', str, "Extra boundary check.")

    @@simpleCSVData.each do |col, str|
      buf = CSV.generate_line(col)
      assert_equal(str, buf)
    end

    @@simpleCSVData.each do |col, str|
      buf = CSV.generate_line(col, ?;)
      assert_equal(str + "\n", ssv2csv(buf))
    end

    @@simpleCSVData.each do |col, str|
      buf = CSV.generate_line(col, ?\t)
      assert_equal(str + "\n", tsv2csv(buf))
    end

    str = CSV.generate_line(['a', 'b'], nil, ?|)
    assert_equal('a,b', str)

    str = CSV.generate_line(['a', 'b'], nil, "a")
    assert_equal('"a",b', str)
  end

  def test_s_generate_row
    buf = ''
    cols = CSV.generate_row([], 0, buf)
    assert_equal(0, cols)
    assert_equal("\n", buf, "Extra boundary check.")

    buf = ''
    cols = CSV.generate_row([], 0, buf, ?;)
    assert_equal(0, cols)
    assert_equal("\n", buf, "Extra boundary check.")

    buf = ''
    cols = CSV.generate_row([], 0, buf, ?\t)
    assert_equal(0, cols)
    assert_equal("\n", buf, "Extra boundary check.")

    buf = ''
    cols = CSV.generate_row([], 0, buf, ?\t, ?|)
    assert_equal(0, cols)
    assert_equal("|", buf, "Extra boundary check.")

    buf = ''
    cols = CSV.generate_row([d('1')], 2, buf)
    assert_equal('1,', buf)

    buf = ''
    cols = CSV.generate_row([d('1')], 2, buf, ?;)
    assert_equal('1;', buf)

    buf = ''
    cols = CSV.generate_row([d('1')], 2, buf, ?\t)
    assert_equal("1\t", buf)

    buf = ''
    cols = CSV.generate_row([d('1')], 2, buf, ?\t, ?|)
    assert_equal("1\t", buf)

    buf = ''
    cols = CSV.generate_row([d('1'), d('2')], 1, buf)
    assert_equal("1\n", buf)

    buf = ''
    cols = CSV.generate_row([d('1'), d('2')], 1, buf, ?;)
    assert_equal("1\n", buf)

    buf = ''
    cols = CSV.generate_row([d('1'), d('2')], 1, buf, ?\t)
    assert_equal("1\n", buf)

    buf = ''
    cols = CSV.generate_row([d('1'), d('2')], 1, buf, ?\t, ?\n)
    assert_equal("1\n", buf)

    buf = ''
    cols = CSV.generate_row([d('1'), d('2')], 1, buf, ?\t, ?\r)
    assert_equal("1\r", buf)

    buf = ''
    cols = CSV.generate_row([d('1'), d('2')], 1, buf, ?\t, ?|)
    assert_equal("1|", buf)

    @@fullCSVData.each do |col, str|
      buf = ''
      cols = CSV.generate_row(col, col.size, buf)
      assert_equal(col.size, cols)
      assert_equal(str + "\n", buf)
    end

    @@fullCSVData.each do |col, str|
      buf = ''
      cols = CSV.generate_row(col, col.size, buf, ?;)
      assert_equal(col.size, cols)
      assert_equal(str + "\n", ssv2csv(buf))
    end

    @@fullCSVData.each do |col, str|
      buf = ''
      cols = CSV.generate_row(col, col.size, buf, ?\t)
      assert_equal(col.size, cols)
      assert_equal(str + "\n", tsv2csv(buf))
    end

    # row separator
    @@fullCSVData.each do |col, str|
      buf = ''
      cols = CSV.generate_row(col, col.size, buf, ?,, ?|)
      assert_equal(col.size, cols)
      assert_equal(str + "|", buf)
    end

    # col and row separator
    @@fullCSVData.each do |col, str|
      buf = ''
      cols = CSV.generate_row(col, col.size, buf, ?\t, ?|)
      assert_equal(col.size, cols)
      assert_equal(str + "|", tsv2csv(buf, ?|))
    end

    buf = ''
    toBe = ''
    cols = 0
    colsToBe = 0
    @@fullCSVData.each do |col, str|
      cols += CSV.generate_row(col, col.size, buf)
      toBe << str << "\n"
      colsToBe += col.size
    end
    assert_equal(colsToBe, cols)
    assert_equal(toBe, buf)

    buf = ''
    toBe = ''
    cols = 0
    colsToBe = 0
    @@fullCSVData.each do |col, str|
      lineBuf = ''
      cols += CSV.generate_row(col, col.size, lineBuf, ?;)
      buf << ssv2csv(lineBuf) << "\n"
      toBe << ssv2csv(lineBuf) << "\n"
      colsToBe += col.size
    end
    assert_equal(colsToBe, cols)
    assert_equal(toBe, buf)

    buf = ''
    toBe = ''
    cols = 0
    colsToBe = 0
    @@fullCSVData.each do |col, str|
      lineBuf = ''
      cols += CSV.generate_row(col, col.size, lineBuf, ?\t)
      buf << tsv2csv(lineBuf) << "\n"
      toBe << tsv2csv(lineBuf) << "\n"
      colsToBe += col.size
    end
    assert_equal(colsToBe, cols)
    assert_equal(toBe, buf)

    buf = ''
    toBe = ''
    cols = 0
    colsToBe = 0
    @@fullCSVData.each do |col, str|
      lineBuf = ''
      cols += CSV.generate_row(col, col.size, lineBuf, ?|)
      buf << tsv2csv(lineBuf, ?|)
      toBe << tsv2csv(lineBuf, ?|)
      colsToBe += col.size
    end
    assert_equal(colsToBe, cols)
    assert_equal(toBe, buf)
  end

  def test_s_parse_line
    @@simpleCSVData.each do |col, str|
      row = CSV.parse_line(str)
      assert_instance_of(Array, row)
      assert_equal(col.size, row.size)
      assert_equal(col, row)
    end

    @@simpleCSVData.each do |col, str|
      str = csv2ssv(str)
      row = CSV.parse_line(str, ?;)
      assert_instance_of(Array, row)
      assert_equal(col.size, row.size, str.inspect)
      assert_equal(col, row, str.inspect)
    end

    @@simpleCSVData.each do |col, str|
      str = csv2tsv(str)
      row = CSV.parse_line(str, ?\t)
      assert_instance_of(Array, row)
      assert_equal(col.size, row.size)
      assert_equal(col, row)
    end

    assert_equal(['a', 'b', 'c'], CSV.parse_line("a,b,c", nil, nil))
    assert_equal(['a', nil], CSV.parse_line("a,b,c", nil, ?b))
    assert_equal(['a', 'b', nil], CSV.parse_line("a,b,c", nil, "c"))
    assert_equal([nil], CSV.parse_line(""))
    assert_equal([nil], CSV.parse_line("\n"))
    assert_equal([""], CSV.parse_line("\"\"\n"))
    
    # Illegal format.
    buf = []
    row = CSV.parse_line("a,b,\"c\"\ra")
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    buf = Array.new
    row = CSV.parse_line("a;b;\"c\"\ra", ?;)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    buf = Array.new
    row = CSV.parse_line("a\tb\t\"c\"\ra", ?\t)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("a,b\"")
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("a;b\"", ?;)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("a\tb\"", ?\t)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("\"a,b\"\r,")
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("\"a;b\"\r;", ?;)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("\"a\tb\"\r\t", ?\t)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("\"a,b\"\r\"")
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("\"a;b\"\r\"", ?;)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)

    row = CSV.parse_line("\"a\tb\"\r\"", ?\t)
    assert_instance_of(Array, row)
    assert_equal(0, row.size)
  end

  def test_s_parse_row
    @@fullCSVData.each do |col, str|
      buf = Array.new
      cols, idx = CSV.parse_row(str + "\r\n", 0, buf)
      assert_equal(cols, buf.size, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf, str.inspect)

      buf = Array.new
      cols, idx = CSV.parse_row(str + "\n", 0, buf, ?,, ?\n)
      assert_equal(cols, buf.size, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf, str.inspect)

      # separator: |
      buf = Array.new
      cols, idx = CSV.parse_row(str + "|", 0, buf, ?,)
      assert_not_equal(col, buf)
      buf = Array.new
      cols, idx = CSV.parse_row(str + "|", 0, buf, ?,, ?|)
      assert_equal(cols, buf.size, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf, str.inspect)
    end

    @@fullCSVData.each do |col, str|
      str = csv2ssv(str)
      buf = Array.new
      cols, idx = CSV.parse_row(str + "\r\n", 0, buf, ?;)
      assert_equal(cols, buf.size, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf, str)
    end

    @@fullCSVData.each do |col, str|
      str = csv2tsv(str)
      buf = Array.new
      cols, idx = CSV.parse_row(str + "\r\n", 0, buf, ?\t)
      assert_equal(cols, buf.size, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf, str)
    end

    @@fullCSVData.each do |col, str|
      str = csv2tsv(str, ?|)
      buf = Array.new
      cols, idx = CSV.parse_row(str + "|", 0, buf, ?\t, ?|)
      assert_equal(cols, buf.size, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf, str)
    end

    buf = []
    CSV.parse_row("a,b,c", 0, buf, nil, nil)
    assert_equal(['a', 'b', 'c'], buf)

    buf = []
    CSV.parse_row("a,b,c", 0, buf, nil, ?b)
    assert_equal(['a', nil], buf)

    buf = []
    CSV.parse_row("a,b,c", 0, buf, nil, "c")
    assert_equal(['a', 'b', nil], buf)

    buf = Array.new
    cols, idx = CSV.parse_row("a,b,\"c\r\"", 0, buf)
    assert_equal(["a", "b", "c\r"], buf.to_a)

    buf = Array.new
    cols, idx = CSV.parse_row("a;b;\"c\r\"", 0, buf, ?;)
    assert_equal(["a", "b", "c\r"], buf.to_a)

    buf = Array.new
    cols, idx = CSV.parse_row("a\tb\t\"c\r\"", 0, buf, ?\t)
    assert_equal(["a", "b", "c\r"], buf.to_a)

    buf = Array.new
    cols, idx = CSV.parse_row("a,b,c\n", 0, buf, ?,, ?\n)
    assert_equal(["a", "b", "c"], buf.to_a)

    buf = Array.new
    cols, idx = CSV.parse_row("a\tb\tc\n", 0, buf, ?\t, ?\n)
    assert_equal(["a", "b", "c"], buf.to_a)

    # Illegal format.
    buf = Array.new
    cols, idx = CSV.parse_row("a,b,c\"", 0, buf)
    assert_equal(0, cols, "Illegal format; unbalanced double-quote.")

    buf = Array.new
    cols, idx = CSV.parse_row("a;b;c\"", 0, buf, ?;)
    assert_equal(0, cols, "Illegal format; unbalanced double-quote.")

    buf = Array.new
    cols, idx = CSV.parse_row("a,b,\"c\"\ra", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a,b,\"c\"\ra", 0, buf, ?;)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a,b\"", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a;b\"", 0, buf, ?;)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("\"a,b\"\r,", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a\r,", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a\r", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a\rbc", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a\r\"\"", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("a\r\rabc,", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("\"a;b\"\r;", 0, buf, ?;)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("\"a,b\"\r\"", 0, buf)
    assert_equal(0, cols)
    assert_equal(0, idx)

    buf = Array.new
    cols, idx = CSV.parse_row("\"a;b\"\r\"", 0, buf, ?;)
    assert_equal(0, cols)
    assert_equal(0, idx)
  end

  def test_s_parse_rowEOF
    @@fullCSVData.each do |col, str|
      if str == ''
	# String "" is not allowed.
	next
      end
      buf = Array.new
      cols, idx = CSV.parse_row(str, 0, buf)
      assert_equal(col.size, cols, "Reported size.")
      assert_equal(col.size, buf.size, "Size.")
      assert_equal(col, buf)
    end
  end

  def test_s_parse_rowConcat
    buf = ''
    toBe = []
    @@fullCSVData.each do |col, str|
      buf  << str << "\r\n"
      toBe.concat(col)
    end
    idx = 0
    cols = 0
    parsed = Array.new
    parsedCols = 0
    begin
      cols, idx = CSV.parse_row(buf, idx, parsed)
      parsedCols += cols
    end while cols > 0
    assert_equal(toBe.size, parsedCols)
    assert_equal(toBe.size, parsed.size)
    assert_equal(toBe, parsed)

    buf = ''
    toBe = []
    @@fullCSVData.each do |col, str|
      buf  << str << "\n"
      toBe.concat(col)
    end
    idx = 0
    cols = 0
    parsed = Array.new
    parsedCols = 0
    begin
      cols, idx = CSV.parse_row(buf, idx, parsed, ?,, ?\n)
      parsedCols += cols
    end while cols > 0
    assert_equal(toBe.size, parsedCols)
    assert_equal(toBe.size, parsed.size)
    assert_equal(toBe, parsed)

    buf = ''
    toBe = []
    @@fullCSVData.sort { |a, b|
      a[0].length <=> b[0].length
    }.each do |col, str|
      buf  << str << "\n"
      toBe.concat(col)
    end
    idx = 0
    cols = 0
    parsed = Array.new
    parsedCols = 0
    begin
      cols, idx = CSV.parse_row(buf, idx, parsed, ?,, ?\n)
      parsedCols += cols
    end while cols > 0
    assert_equal(toBe.size, parsedCols)
    assert_equal(toBe.size, parsed.size)
    assert_equal(toBe, parsed)

    buf = ''
    toBe = []
    @@fullCSVData.each do |col, str|
      buf  << str << "|"
      toBe.concat(col)
    end
    idx = 0
    cols = 0
    parsed = []
    parsedCols = 0
    begin
      cols, idx = CSV.parse_row(buf, idx, parsed, ?,, ?|)
      parsedCols += cols
    end while cols > 0
    assert_equal(toBe.size, parsedCols)
    assert_equal(toBe.size, parsed.size)
    assert_equal(toBe, parsed)
  end

  def test_utf8
    rows = []
    CSV.open(@bomfile, "r") do |row|
      rows << row.to_a
    end
    assert_equal([["foo"], ["bar"]], rows)

    rows = []
    file = File.open(@bomfile)
    CSV::Reader.parse(file) do |row|
      rows << row.to_a
    end
    assert_equal([["foo"], ["bar"]], rows)
    file.close
  end

  def test_macCR
    rows = []
    CSV.open(@macfile, "r", ?,, ?\r) do |row|
      rows << row.to_a
    end
    assert_equal([["Avenches", "aus Umgebung"], ["Bad Hersfeld", "Ausgrabung"]], rows)

    rows = []
    assert_raises(CSV::IllegalFormatError) do
      CSV.open(@macfile, "r") do |row|
        rows << row.to_a
      end
      assert_equal([["Avenches", "aus Umgebung\r\"Bad Hersfeld", "Ausgrabung"]], rows)
    end

    rows = []
    file = File.open(@macfile)
    begin
      CSV::Reader.parse(file, ?,, ?\r) do |row|
        rows << row.to_a
      end
      assert_equal([["Avenches", "aus Umgebung"], ["Bad Hersfeld", "Ausgrabung"]], rows)
    ensure
      file.close
    end

    rows = []
    file = File.open(@macfile)
    begin
      assert_raises(CSV::IllegalFormatError) do
        CSV::Reader.parse(file, ?,) do |row|
          rows << row.to_a
        end
        assert_equal([["Avenches", "aus Umgebung\r\"Bad Hersfeld", "Ausgrabung"]], rows)
      end
    ensure
      file.close
    end
  end


  #### CSV unit test

  InputStreamPattern = '0123456789'
  InputStreamPatternSize = InputStreamPattern.size
  def expChar(idx)
    InputStreamPattern[idx % InputStreamPatternSize]
  end

  def expStr(idx, n)
    if n > InputStreamPatternSize
      InputStreamPattern + expStr(0, n - InputStreamPatternSize)
    else
      InputStreamPattern[idx % InputStreamPatternSize, n]
    end
  end

  def setupInputStream(size, bufSize = nil)
    setBufSize(bufSize) if bufSize
    m = ((size / InputStreamPatternSize) + 1).to_i
    File.open(@outfile, "wb") do |f|
      f << (InputStreamPattern * m)[0, size]
    end
    file = File.open(@outfile, "rb")
    buf = CSV::IOBuf.new(file)
    if block_given?
      yield(buf)
      file.close
      nil
    else
      buf
    end
  end

  def setBufSize(size)
    CSV::StreamBuf.module_eval('remove_const("BufSize")')
    CSV::StreamBuf.module_eval("BufSize = #{ size }")
  end

  class StrBuf < CSV::StreamBuf
  private
    def initialize(string)
      @str = string
      @idx = 0
      super()
    end

    def read(size)
      str = @str[@idx, size]
      if str.empty?
        nil
      else
        @idx += str.size
        str
      end
    end
  end

  class ErrBuf < CSV::StreamBuf
    class Error < RuntimeError; end
  private
    def initialize
      @first = true
      super()
    end

    def read(size)
      if @first
	@first = false
	"a" * size
      else
	raise ErrBuf::Error.new
      end
    end
  end

  def test_StreamBuf_MyBuf
    # At first, check ruby's behaviour.
    s = "abc"
    assert_equal(?a, s[0])
    assert_equal(?b, s[1])
    assert_equal(?c, s[2])
    assert_equal(nil, s[3])
    assert_equal("a", s[0, 1])
    assert_equal("b", s[1, 1])
    assert_equal("c", s[2, 1])
    assert_equal("", s[3, 1])
    assert_equal(nil, s[4, 1])

    s = StrBuf.new("abc")
    assert_equal(?a, s[0])
    assert_equal(?b, s.get(1))
    assert_equal(?c, s[2])
    assert_equal(nil, s.get(3))
    assert_equal("a", s[0, 1])
    assert_equal("b", s.get(1, 1))
    assert_equal("c", s[2, 1])
    assert_equal("", s.get(3, 1))
    assert_equal(nil, s[4, 1])

    dropped = s.drop(1)
    assert_equal(1, dropped)
    assert_equal(?b, s[0])
    assert(!s.is_eos?)
    dropped = s.drop(1)
    assert_equal(1, dropped)
    assert_equal(?c, s[0])
    assert(!s.is_eos?)
    dropped = s.drop(1)
    assert_equal(1, dropped)
    assert_equal(nil, s[0])
    assert(s.is_eos?)
    dropped = s.drop(1)
    assert_equal(0, dropped)
    assert_equal(nil, s[0])
    assert(s.is_eos?)

    s = StrBuf.new("")
    assert_equal(nil, s[0])

    s = StrBuf.new("")
    dropped = s.drop(1)
    assert_equal(0, dropped)

    assert_raises(TestCSV::ErrBuf::Error) do
      s = ErrBuf.new
      s[1024]
    end

    assert_raises(TestCSV::ErrBuf::Error) do
      s = ErrBuf.new
      s.drop(1024)
    end
  end

  def test_StreamBuf_AREF # '[idx]'
    setupInputStream(22, 1024) do |s|
      [0, 1, 9, 10, 19, 20, 21].each do |idx|
	assert_equal(expChar(idx), s[idx], idx.to_s)
      end
      [22, 23].each do |idx|
	assert_equal(nil, s[idx], idx.to_s)
      end
      assert_equal(nil, s[-1])
    end

    setupInputStream(22, 1) do |s|
      [0, 1, 9, 10, 19, 20, 21].each do |idx|
	assert_equal(expChar(idx), s[idx], idx.to_s)
      end
      [22, 23].each do |idx|
	assert_equal(nil, s[idx], idx.to_s)
      end
    end

    setupInputStream(1024, 1) do |s|
      [1023, 0].each do |idx|
	assert_equal(expChar(idx), s[idx], idx.to_s)
      end
      [1024, 1025].each do |idx|
	assert_equal(nil, s[idx], idx.to_s)
      end
    end

    setupInputStream(1, 1) do |s|
      [0].each do |idx|
	assert_equal(expChar(idx), s[idx], idx.to_s)
      end
      [1, 2].each do |idx|
	assert_equal(nil, s[idx], idx.to_s)
      end
    end
  end

  def test_StreamBuf_AREF_n # '[idx, n]'
    # At first, check ruby's behaviour.
    assert_equal("", "abc"[3, 1])
    assert_equal(nil, "abc"[4, 1])
    
    setupInputStream(22, 1024) do |s|
      [0, 1, 9, 10, 19, 20, 21].each do |idx|
	assert_equal(expStr(idx, 1), s[idx, 1], idx.to_s)
      end
      assert_equal("", s[22, 1])
      assert_equal(nil, s[23, 1])
    end

    setupInputStream(22, 1) do |s|
      [0, 1, 9, 10, 19, 20, 21].each do |idx|
	assert_equal(expStr(idx, 1), s[idx, 1], idx.to_s)
      end
      assert_equal("", s[22, 1])
      assert_equal(nil, s[23, 1])
    end

    setupInputStream(1024, 1) do |s|
      [1023, 0].each do |idx|
	assert_equal(expStr(idx, 1), s[idx, 1], idx.to_s)
      end
      assert_equal("", s[1024, 1])
      assert_equal(nil, s[1025, 1])
    end

    setupInputStream(1, 1) do |s|
      [0].each do |idx|
	assert_equal(expStr(idx, 1), s[idx, 1], idx.to_s)
      end
      assert_equal("", s[1, 1])
      assert_equal(nil, s[2, 1])
    end

    setupInputStream(22, 11) do |s|
      [0, 1, 10, 11, 20].each do  |idx|
	assert_equal(expStr(idx, 2), s[idx, 2], idx.to_s)
      end
      assert_equal(expStr(21, 1), s[21, 2])

      assert_equal(expStr(0, 12), s[0, 12])
      assert_equal(expStr(10, 12), s[10, 12])
      assert_equal(expStr(10, 12), s[10, 13])
      assert_equal(expStr(10, 12), s[10, 14])
      assert_equal(expStr(10, 12), s[10, 1024])

      assert_equal(nil, s[0, -1])
      assert_equal(nil, s[21, -1])

      assert_equal(nil, s[-1, 10])
      assert_equal(nil, s[-1, -1])
    end
  end

  def test_StreamBuf_get
    setupInputStream(22, 1024) do |s|
      [0, 1, 9, 10, 19, 20, 21].each do |idx|
	assert_equal(expChar(idx), s.get(idx), idx.to_s)
      end
      [22, 23].each do |idx|
	assert_equal(nil, s.get(idx), idx.to_s)
      end
      assert_equal(nil, s.get(-1))
    end
  end
  
  def test_StreamBuf_get_n
    setupInputStream(22, 1024) do |s|
      [0, 1, 9, 10, 19, 20, 21].each do |idx|
	assert_equal(expStr(idx, 1), s.get(idx, 1), idx.to_s)
      end
      assert_equal("", s.get(22, 1))
      assert_equal(nil, s.get(23, 1))

      assert_equal(nil, s.get(-1, 1))
      assert_equal(nil, s.get(-1, -1))
    end
  end

  def test_StreamBuf_drop
    setupInputStream(22, 1024) do |s|
      assert_equal(expChar(0), s[0])
      assert_equal(expChar(21), s[21])
      assert_equal(nil, s[22])

      dropped = s.drop(-1)
      assert_equal(0, dropped)
      assert_equal(expChar(0), s[0])

      dropped = s.drop(0)
      assert_equal(0, dropped)
      assert_equal(expChar(0), s[0])

      dropped = s.drop(1)
      assert_equal(1, dropped)
      assert_equal(expChar(1), s[0])
      assert_equal(expChar(2), s[1])

      dropped = s.drop(1)
      assert_equal(1, dropped)
      assert_equal(expChar(2), s[0])
      assert_equal(expChar(3), s[1])
    end

    setupInputStream(4, 2) do |s|
      dropped = s.drop(2)
      assert_equal(2, dropped)
      assert_equal(expChar(2), s[0])
      assert_equal(expChar(3), s[1])
      dropped = s.drop(1)
      assert_equal(1, dropped)
      assert_equal(expChar(3), s[0])
      assert_equal(nil, s[1])
      dropped = s.drop(1)
      assert_equal(1, dropped)
      assert_equal(nil, s[0])
      assert_equal(nil, s[1])
      dropped = s.drop(0)
      assert_equal(0, dropped)
      assert_equal(nil, s[0])
      assert_equal(nil, s[1])
    end

    setupInputStream(6, 3) do |s|
      dropped = s.drop(2)
      assert_equal(2, dropped)
      dropped = s.drop(2)
      assert_equal(2, dropped)
      assert_equal(expChar(4), s[0])
      assert_equal(expChar(5), s[1])
      dropped = s.drop(3)
      assert_equal(2, dropped)
      assert_equal(nil, s[0])
      assert_equal(nil, s[1])
    end
  end

  def test_StreamBuf_is_eos?
    setupInputStream(3, 1024) do |s|
      assert(!s.is_eos?)
      s.drop(1)
      assert(!s.is_eos?)
      s.drop(1)
      assert(!s.is_eos?)
      s.drop(1)
      assert(s.is_eos?)
      s.drop(1)
      assert(s.is_eos?)
    end

    setupInputStream(3, 2) do |s|
      assert(!s.is_eos?)
      s.drop(1)
      assert(!s.is_eos?)
      s.drop(1)
      assert(!s.is_eos?)
      s.drop(1)
      assert(s.is_eos?)
      s.drop(1)
      assert(s.is_eos?)
    end
  end

  def test_StreamBuf_s_new
    # NotImplementedError should be raised from StreamBuf#read.
    assert_raises(NotImplementedError) do
      CSV::StreamBuf.new
    end
  end

  def test_IOBuf_close
    f = File.open(@outfile, "wb")
    f << "tst"
    f.close

    f = File.open(@outfile, "rb")
    iobuf = CSV::IOBuf.new(f)
    iobuf.close
    assert(true)	# iobuf.close does not raise any exception.
    f.close
  end

  def test_IOBuf_s_new
    iobuf = CSV::IOBuf.new(Tempfile.new("in.csv"))
    assert_instance_of(CSV::IOBuf, iobuf)
  end


  #### CSV functional test

  # sample data
  #
  #  1      2       3         4       5        6      7    8
  # +------+-------+---------+-------+--------+------+----+------+
  # | foo  | "foo" | foo,bar | ""    |(empty) |(null)| \r | \r\n |
  # +------+-------+---------+-------+--------+------+----+------+
  # | NaHi | "Na"  | Na,Hi   | \r.\n | \r\n\n | "    | \n | \r\n |
  # +------+-------+---------+-------+--------+------+----+------+
  #
  def test_s_parseAndCreate
    colSize = 8
    csvStr = "foo,!!!foo!!!,!foo,bar!,!!!!!!,!!,,!\r!,!\r\n!\nNaHi,!!!Na!!!,!Na,Hi!,!\r.\n!,!\r\n\n!,!!!!,!\n!,!\r\n!".gsub!('!', '"')
    csvStrTerminated = csvStr + "\n"

    myStr = csvStr.dup
    res1 = []; res2 = []
    idx = 0
    col, idx = CSV::parse_row(myStr, 0, res1)
    col, idx = CSV::parse_row(myStr, idx, res2)

    buf = ''
    col = CSV::generate_row(res1, colSize, buf)
    col = CSV::generate_row(res2, colSize, buf)
    assert_equal(csvStrTerminated, buf)

    parsed = []
    CSV::Reader.parse(csvStrTerminated) do |row|
      parsed << row
    end

    buf = ''
    CSV::Writer.generate(buf) do |writer|
      parsed.each do |row|
	writer.add_row(row)
      end
    end
    assert_equal(csvStrTerminated, buf)

    buf = ''
    CSV::Writer.generate(buf) do |writer|
      parsed.each do |row|
	writer << row
      end
    end
    assert_equal(csvStrTerminated, buf)
  end

  def test_writer_fs_rs_generate
    buf = ''
    CSV::Writer.generate(buf, ",,") do |writer|
      writer << []
    end
    assert_equal("\n", buf)

    buf = ''
    CSV::Writer.generate(buf, ",,") do |writer|
      writer << [] << []
    end
    assert_equal("\n\n", buf)

    buf = ''
    CSV::Writer.generate(buf, ",,") do |writer|
      writer << [1]
    end
    assert_equal("1\n", buf)

    buf = ''
    CSV::Writer.generate(buf, ",,") do |writer|
      writer << [1, 2, 3]
      writer << [4, ",,", 5]
    end
    assert_equal("1,,2,,3\n4,,\",,\",,5\n", buf)

    buf = ''
    CSV::Writer.generate(buf, ",,:", ",,;") do |writer|
      writer << [nil, nil, nil]
      writer << [nil, ",,", nil]
    end
    assert_equal(",,:,,:,,;,,:,,,,:,,;", buf)

    buf = ''
    CSV::Writer.generate(buf, "---") do |writer|
      writer << [1, 2, 3]
      writer << [4, "---\"---", 5]
    end
    assert_equal("1---2---3\n4---\"---\"\"---\"---5\n", buf)

    buf = ''
    CSV::Writer.generate(buf, nil) do |writer|
      writer << [1, 2, 3]
      writer << [4, ",\",", 5]
    end
    assert_equal("1,2,3\n4,\",\"\",\",5\n", buf)
  end

  def test_writer_fs_rs_parse
    reader = CSV::Reader.create('a||b--c||d', '||', '--')
    assert_equal(['a', 'b'], reader.shift)
    assert_equal(['c', 'd'], reader.shift)

    reader = CSV::Reader.create("a@|b@-c@|d", "@|", "@-")
    assert_equal(['a', 'b'], reader.shift)
    assert_equal(['c', 'd'], reader.shift)

    reader = CSV::Reader.create("ababfsababrs", "abfs", "abrs")
    assert_equal(['ab', 'ab'], reader.shift)

    reader = CSV::Reader.create('"ab"abfsababrs', "abfs", "abrs")
    assert_equal(['ab', 'ab'], reader.shift)

    reader = CSV::Reader.create('"ab"aabfsababrs', "abfs", "abrs")
    assert_raises(CSV::IllegalFormatError) do
      reader.shift
    end

    # fs match while matching rs progress
    reader = CSV::Reader.create("ab,ababrs", nil, "abrs")
    assert_equal(['ab', 'ab'], reader.shift)

    reader = CSV::Reader.create(',ababrs', nil, "abrs")
    assert_equal([nil, 'ab'], reader.shift)

    reader = CSV::Reader.create('"",ababrs', nil, "abrs")
    assert_equal(['', 'ab'], reader.shift)

    reader = CSV::Reader.create('ab,"ab"abrs', nil, "abrs")
    assert_equal(['ab', 'ab'], reader.shift)

    reader = CSV::Reader.create('ab,"ab"aabrs', nil, "abrs")
    assert_raises(CSV::IllegalFormatError) do
      reader.shift
    end

    # rs match while matching fs progress
    reader = CSV::Reader.create("ab|abc", 'ab-', "ab|")
    assert_equal([nil], reader.shift)
    assert_equal(['abc'], reader.shift)

    reader = CSV::Reader.create("ab\ncdabcef", "abc", "\n")
    assert_equal(['ab'], reader.shift)
    assert_equal(['cd', "ef"], reader.shift)

    # EOF while fs/rs matching
    reader = CSV::Reader.create("ab", 'ab-', "xyz")
    assert_equal(['ab'], reader.shift)

    reader = CSV::Reader.create("ab", 'xyz', "ab|")
    assert_equal(['ab'], reader.shift)

    reader = CSV::Reader.create("ab", 'ab-', "ab|")
    assert_equal(['ab'], reader.shift)

    reader = CSV::Reader.create(",,:,,:,,;,,:,,,,:,,;", ",,:", ",,;")
    assert_equal([nil, nil, nil], reader.shift)
    assert_equal([nil, ",,", nil], reader.shift)
  end

  def test_s_foreach
    File.open(@outfile, "w") do |f|
      f << "1,2,3\n4,5,6"
    end
    row = []
    CSV.foreach(@outfile) { |line|
      row << line
    }
    assert_equal([['1', '2', '3'], ['4', '5', '6']], row)

    File.open(@outfile, "w") do |f|
      f << "1,2,3\r4,5,6"
    end
    row = []
    CSV.foreach(@outfile, "\r") { |line|
      row << line
    }
    assert_equal([['1', '2', '3'], ['4', '5', '6']], row)
  end

  def test_s_readlines
    File.open(@outfile, "w") do |f|
      f << "1,2,3\n4,5,6"
    end
    assert_equal([["1", "2", "3"], ["4", "5", "6"]], CSV.readlines(@outfile))
    assert_equal([["1", "2", nil], [nil, "5", "6"]], CSV.readlines(@outfile, "3\n4"))
  end

  def test_s_read
    File.open(@outfile, "w") do |f|
      f << "1,2,3\n4,5,6"
    end
    assert_equal([["1", "2", "3"], ["4", "5", "6"]], CSV.read(@outfile))
    assert_equal([["1", "2"]], CSV.read(@outfile, 3))
    assert_equal([[nil], ["4", nil]], CSV.read(@outfile, 3, 5))
  end
end
