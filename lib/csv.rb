# CSV -- module for generating/parsing CSV data.
  
# $Id$
  
# This module is copyrighted free software by NAKAMURA, Hiroshi.
# You can redistribute it and/or modify it under the same term as Ruby.
  
  
class CSV
public

  # DESCRIPTION
  #   CSV::Cell -- Describes 1 cell of CSV.
  #   
  class Cell
  public
  
    # Datum as string.
    attr_accessor :data
    
    # Is this datum null?
    attr_accessor :is_null

    # SYNOPSIS
    #   cell = CSV::Cell.new(data = '', is_null = true)
    #
    # ARGS
    #   data: datum as String
    #   is_null: is this datum null?
    #
    # RETURNS
    #   cell: Created instance.
    #
    # DESCRIPTION
    #   Create instance.  If is_null is true, datum is stored in the instance
    #   created but it should be treated as 'NULL'.
    #   
    def initialize(data = '', is_null = true)
      @data = data
      @is_null = is_null
    end

    # SYNOPSIS
    #   CSV::Cell#match(rhs)
    #
    # ARGS
    #   rhs: an instance of CSV::Cell to be compared.
    #
    # RETURNS
    #   true/false.  See the souce if you want to know matching algorithm.
    #
    # DESCRIPTION
    #   Compare another cell with me.  Bare in mind Null matches with Null
    #   using this method.  Use CSV::Cell#== if you want Null never matches
    #   with other data including Null.
    #
    def match(rhs)
      if @is_null and rhs.is_null
        true
      elsif @is_null or rhs.is_null
        false
      else
        @data == rhs.data
      end
    end

    # SYNOPSIS
    #   CSV::Cell#==(rhs)
    #
    # ARGS
    #   rhs: an instance of CSV::Cell to be compared.
    #
    # RETURNS
    #   true/false.  See the souce if you want to know matching algorithm.
    #
    # DESCRIPTION
    #   Compare another cell with me.  Bare in mind Null is not match with
    #   Null using this method.  Null never matches with other data including
    #   Null.  Use CSV::Cell#match if you want Null matches with Null.
    #
    def ==(rhs)
      if @is_null or rhs.is_null
        false
      else
        @data == rhs.data
      end
    end
  end
  

  # DESCRIPTION
  #   CSV::Row -- Describes a row of CSV.  Each element must be a CSV::Cell.
  #   
  class Row < Array
  public

    # SYNOPSIS
    #   CSV::Row#to_a
    #
    # RETURNS
    #   An Array of String.
    #
    # DESCRIPTION
    #   Convert CSV::Cell to String.  Null is converted to nil.
    #
    def to_a
      self.collect { |cell| cell.is_null ? nil : cell.data }
    end

    # SYNOPSIS
    #   CSV::Row#match(rhs)
    #
    # ARGS
    #   rhs: an Array of cells.  Each cell is a instance of CSV::Cell.
    #
    # RETURNS
    #   true/false.  See the souce if you want to know matching algorithm.
    #
    # DESCRIPTION
    #   Compare another row with me.
    #
    def match(rhs)
      if self.size != rhs.size
        return false
      end
      for idx in 0...(self.size)
        unless self[idx].match(rhs[idx])
          return false
        end
      end
      true
    end
  end


  # SYNOPSIS
  #   1. reader = CSV.open(filename, 'r')
  #
  #   2. CSV.open(filename, 'r') do |row|
  #        ...
  #      end
  #
  #   3. writer = CSV.open(filename, 'w')
  #
  #   4. CSV.open(filename, 'w') do |writer|
  #        ...
  #      end
  #
  # ARGS
  #   filename: filename to open.
  #   mode: 'r' for read (parse)
  #         'w' for write (generate)
  #   row: an Array of cells which is a parsed line.
  #   writer: Created writer instance.  See CSV::Writer#<< and
  #     CSV::Writer#add_row to know how to generate CSV string.
  #
  # RETURNS
  #   reader: Create reader instance.  To get parse result, see
  #     CSV::Reader#each.
  #   writer: Created writer instance.  See CSV::Writer#<< and
  #     CSV::Writer#add_row to know how to generate CSV string.
  #
  # DESCRIPTION
  #   Open a CSV formatted file to read or write.
  #
  # EXAMPLE 1
  #   reader = CSV.open('csvfile.csv', 'r')
  #   row1 = reader.shift
  #   row2 = reader.shift
  #   if row2.empty?
  #     p 'row2 not find.'
  #   end
  #   reader.close
  #   
  # EXAMPLE 2
  #   CSV.open('csvfile.csv', 'r') do |row|
  #     p row
  #   end
  #      
  # EXAMPLE 3
  #   writer = CSV.open('csvfile.csv', 'w')
  #   writer << ['r1c1', 'r1c2'] << ['r2c1', 'r2c2'] << [nil, nil]
  #   writer.close
  #   
  # EXAMPLE 4
  #   CSV.open('csvfile.csv', 'w') do |writer|
  #     writer << ['r1c1', 'r1c2']
  #     writer << ['r2c1', 'r2c2']
  #     writer << [nil, nil]
  #   end
  #
  def CSV.open(filename, mode, col_sep = ?,, row_sep = nil, &block)
    if mode == 'r' or mode == 'rb'
      open_reader(filename, col_sep, row_sep, &block)
    elsif mode == 'w' or mode == 'wb'
      open_writer(filename, col_sep, row_sep, &block)
    else
      raise ArgumentError.new("'mode' must be 'r', 'rb', 'w', or 'wb'")
    end
  end

  def CSV.parse(filename, col_sep = ?,, row_sep = nil, &block)
    open_reader(filename, col_sep, row_sep, &block)
  end

  def CSV.generate(filename, col_sep = ?,, row_sep = nil, &block)
    open_writer(filename, col_sep, row_sep, &block)
  end

  # Private class methods.
  class << self
  private
    def open_reader(filename, col_sep, row_sep, &block)
      file = File.open(filename, 'rb')
      if block
        begin
          CSV::Reader.parse(file, col_sep, row_sep) do |row|
            yield(row)
          end
        ensure
          file.close
        end
        nil
      else
        reader = CSV::Reader.create(file, col_sep, row_sep)
        reader.close_on_terminate
        reader
      end
    end

    def open_writer(filename, col_sep, row_sep, &block)
      file = File.open(filename, 'wb')
      if block
        begin
          CSV::Writer.generate(file, col_sep, row_sep) do |writer|
            yield(writer)
          end
        ensure
          file.close
        end
        nil
      else
        writer = CSV::Writer.create(file, col_sep, row_sep) 
        writer.close_on_terminate
        writer
      end
    end
  end


  # DESCRIPTION
  #   CSV::Reader -- CSV formatted string/stream reader.
  #   
  # EXAMPLE
  #   Read CSV lines untill the first column is 'stop'.
  #
  #   CSV::Reader.parse(File.open('bigdata', 'rb')) do |row|
  #     p row
  #     break if !row[0].is_null && row[0].data == 'stop'
  #   end
  #
  class Reader
    include Enumerable
  public

    # SYNOPSIS
    #   reader = CSV::Reader.create(str_or_readable)
    #
    # ARGS
    #   str_or_readable: a CSV data to be parsed.  A String or an IO.
    #
    # RETURNS
    #   reader: Created instance.
    #
    # DESCRIPTION
    #   Create instance.  To get parse result, see CSV::Reader#each.
    #   
    def Reader.create(str_or_readable, col_sep = ?,, row_sep = nil)
      case str_or_readable
      when IO
        IOReader.new(str_or_readable, col_sep, row_sep)
      when String
        StringReader.new(str_or_readable, col_sep, row_sep)
      else
        IOReader.new(str_or_readable, col_sep, row_sep)
      end
    end

    # SYNOPSIS
    #   CSV::Reader.parse(str_or_readable) do |row|
    #     ...
    #   end
    #
    # ARGS
    #   str_or_readable: a CSV data to be parsed.  A String or an IO.
    #   row: a CSV::Row; an Array of a CSV::Cell in a line.
    #
    # RETURNS
    #   nil
    #
    # DESCRIPTION
    #   Parse CSV data and get lines.  Caller block is called for each line
    #   with an argument which is a chunk of cells in a row.
    #
    #   Block value is always nil.  Rows are not cached for performance
    #   reason.
    #
    def Reader.parse(str_or_readable, col_sep = ?,, row_sep = nil)
      reader = create(str_or_readable, col_sep, row_sep)
      reader.each do |row|
        yield(row)
      end
      reader.close
      nil
    end

    # SYNOPSIS
    #   CSV::Reader#each do |row|
    #     ...
    #   end
    #
    # ARGS
    #   row: a CSV::Row; an Array of a CSV::Cell in a line.
    #
    # RETURNS
    #   nil
    #
    # DESCRIPTION
    #   Caller block is called for each line with an argument which is a chunk
    #   of cells in a row.
    #
    #   Block value is always nil.  Rows are not cached for performance
    #   reason.
    #   
    def each
      while true
        row = Row.new
        parsed_cells = get_row(row)
        if parsed_cells == 0
          break
        end
        yield(row)
      end
      nil
    end

    # SYNOPSIS
    #   cell = CSV::Reader#shift
    #
    # RETURNS
    #   cell: a CSV::Row; an Array of a CSV::Cell.
    #
    # DESCRIPTION
    #   Extract cells of next line.
    #   
    def shift
      row = Row.new
      parsed_cells = get_row(row)
      row
    end

    # SYNOPSIS
    #   CSV::Reader#close
    #
    # RETURNS
    #   nil
    #
    # DESCRIPTION
    #   Close this reader.
    #   
    def close
      terminate
    end

  private
    def initialize(dev)
      raise RuntimeError.new('Do not instanciate this class directly.')
    end

    def get_row(row)
      raise NotImplementedError.new('Method get_row must be defined in a derived class.')
    end

    def terminate
      # Define if needed.
    end
  end
  

  # DESCRIPTION
  #   CSV::StringReader -- CSV formatted stream reader.
  #   
  # EXAMPLE
  #   Read CSV lines untill the first column is 'stop'.
  #
  #   CSV::Reader.parse(File.open('bigdata', 'rb')) do |row|
  #     p row
  #     break if !row[0].is_null && row[0].data == 'stop'
  #   end
  #
  class StringReader < Reader
  public

    # SYNOPSIS
    #   reader = CSV::StringReader.new(string)
    #
    # ARGS
    #   string: a CSV String to be parsed.
    #
    # RETURNS
    #   reader: Created instance.
    #
    # DESCRIPTION
    #   Create instance.  To get parse result, see CSV::Reader#each.
    #   
    def initialize(string, col_sep = ?,, row_sep = nil)
      @col_sep = col_sep
      @row_sep = row_sep
      @dev = string
      @idx = 0
      if @dev[0, 3] == "\xef\xbb\xbf"
        @idx += 3
      end
    end

  private
    def get_row(row)
      parsed_cells, next_idx = CSV.parse_row(@dev, @idx, row, @col_sep, @row_sep)
      if parsed_cells == 0 && next_idx == 0 && @idx != @dev.size
        raise IllegalFormatError.new
      end
      @idx = next_idx
      parsed_cells
    end
  end


  # DESCRIPTION
  #   CSV::IOReader -- CSV formatted stream reader.
  #   
  # EXAMPLE
  #   Read CSV lines untill the first column is 'stop'.
  #
  #   CSV::Reader.parse(File.open('bigdata', 'rb')) do |row|
  #     p row
  #     break if !row[0].is_null && row[0].data == 'stop'
  #   end
  #
  class IOReader < Reader
  public

    # SYNOPSIS
    #   reader = CSV::IOReader.new(io)
    #
    # ARGS
    #   io: a CSV data to be parsed.  Must be an IO. (io#read is called.)
    #
    # RETURNS
    #   reader: Created instance.
    #
    # DESCRIPTION
    #   Create instance.  To get parse result, see CSV::Reader#each.
    #   
    def initialize(io, col_sep = ?,, row_sep = nil)
      @io = io
      @io.binmode if @io.respond_to?(:binmode)
      @col_sep = col_sep
      @row_sep = row_sep
      @dev = CSV::IOBuf.new(@io)
      @idx = 0
      if @dev[0] == 0xef and @dev[1] == 0xbb and @dev[2] == 0xbf
        @idx += 3
      end
      @close_on_terminate = false
    end

    # SYNOPSIS
    #   CSV::IOReader#close_on_terminate
    #
    # RETURNS
    #   true
    #
    # DESCRIPTION
    #   Tell this reader to close the IO when terminated (Triggered by invoking
    #   CSV::IOReader#close).
    #   
    def close_on_terminate
      @close_on_terminate = true
    end

  private
    def get_row(row)
      parsed_cells, next_idx = CSV.parse_row(@dev, @idx, row, @col_sep, @row_sep)
      if parsed_cells == 0 && next_idx == 0 && !@dev.is_eos?
        raise IllegalFormatError.new
      end
      dropped = @dev.drop(next_idx)
      @idx = next_idx - dropped
      parsed_cells
    end

    def terminate
      if @close_on_terminate
        @io.close
      end

      if @dev
        @dev.close
      end
    end
  end


  # DESCRIPTION
  #   CSV::Writer -- CSV formatted string/stream writer.
  #   
  # EXAMPLE
  #   Write rows to 'csvout' file.
  #
  #   outfile = File.open('csvout', 'wb')
  #   CSV::Writer.generate(outfile) do |csv|
  #     csv << ['c1', nil, '', '"', "\r\n", 'c2']
  #     # or
  #     csv.add_row [
  #       CSV::Cell.new('c1', false),
  #       CSV::Cell.new('dummy', true),
  #       CSV::Cell.new('', false),
  #       CSV::Cell.new('"', false),
  #       CSV::Cell.new("\r\n", false)
  #       CSV::Cell.new('c2', false)
  #     ]
  #     ...
  #     ...
  #   end
  #
  #   outfile.close
  #
  class Writer
  public

    # SYNOPSIS
    #   writer = CSV::Writer.create(str_or_readable)
    #
    # ARGS
    #   str_or_writable: device for generated CSV string.  Must respond to
    #     '<<(string)'.
    #
    # RETURNS
    #   writer: Created instance.
    #
    # DESCRIPTION
    #   Create instance.  To add CSV data to generate CSV string, see
    #   CSV::Writer#<< or CSV::Writer#add_row.
    #   
    def Writer.create(str_or_writable, col_sep = ?,, row_sep = nil)
      BasicWriter.new(str_or_writable, col_sep, row_sep)
    end

    # SYNOPSIS
    #   CSV::Writer.generate(str_or_writable) do |writer|
    #     ...
    #   end
    #
    # ARGS
    #   str_or_writable: device for generated CSV string.  Must respond to
    #     '<<(string)'.
    #   writer: Created writer instance.  See CSV::Writer#<< and
    #     CSV::Writer#add_row to know how to generate CSV string.
    #
    # RETURNS
    #   nil
    #
    # DESCRIPTION
    #   Create writer instance.  Caller block is called with the new instance.
    #   To add CSV data to generate CSV string, see CSV::Writer#<< or
    #   CSV::Writer#add_row.
    #   
    def Writer.generate(str_or_writable, col_sep = ?,, row_sep = nil)
      writer = Writer.create(str_or_writable, col_sep, row_sep)
      yield(writer)
      writer.close
      nil
    end

    # SYNOPSIS
    #   CSV::Writer#<<(row)
    #
    # ARGS
    #   row: an Array of a String.
    #
    # RETURNS
    #   self
    #
    # DESCRIPTION
    #   Dump CSV stream to the device.  Argument is an array of a String like
    #   ['c1', 'c2', 'c3'].
    #   
    def <<(ary)
      row = ary.collect { |item|
        if item.is_a?(Cell)
          item
        elsif (item.nil?)
          Cell.new('', true)
        else
          Cell.new(item.to_s, false)
        end
      }
      CSV.generate_row(row, row.size, @dev, @col_sep, @row_sep)
      self
    end

    # SYNOPSIS
    #   CSV::Writer#<<(row)
    #
    # ARGS
    #   row: an Array of a CSV::Cell.
    #
    # RETURNS
    #   self
    #
    # DESCRIPTION
    #   Dump CSV stream to the device.  Argument is an array of a CSV::Cell
    #   like [CSV::Cell.new('c1', false), CSV::Cell.new('dummy', true)].
    #   (Formar is 'c1' and latter is Null.)
    #   
    def add_row(row)
      CSV.generate_row(row, row.size, @dev, @col_sep, @row_sep)
      self
    end

    # SYNOPSIS
    #   CSV::Writer#close
    #
    # RETURNS
    #   nil
    #
    # DESCRIPTION
    #   Close this writer.
    #   
    def close
      terminate
    end

  private
    def initialize(dev)
      raise RuntimeError.new('Do not instanciate this class directly.')
    end

    def terminate
      # Define if needed.
    end
  end


  # DESCRIPTION
  #   CSV::BasicWriter -- CSV formatted string/stream writer using <<.
  #   
  class BasicWriter < Writer
  public

    # SYNOPSIS
    #   writer = CSV::BasicWriter.new(str_or_writable)
    #
    # ARGS
    #   str_or_writable: device for generated CSV string.  Must respond to
    #     '<<(string)'.
    #
    # RETURNS
    #   writer: Created instance.
    #
    # DESCRIPTION
    #   Create instance.  To add CSV data to generate CSV string, see
    #   CSV::Writer#<< or CSV::Writer#add_row.
    #   
    def initialize(str_or_writable, col_sep = ?,, row_sep = nil)
      @col_sep = col_sep
      @row_sep = row_sep
      @dev = str_or_writable
      @dev.binmode if @dev.respond_to?(:binmode)
      @close_on_terminate = false
    end

    # SYNOPSIS
    #   CSV::BasicWriter#close_on_terminate
    #
    # RETURNS
    #   true
    #
    # DESCRIPTION
    #   Tell this writer to close the IO when terminated (Triggered by invoking
    #   CSV::BasicWriter#close).
    #   
    def close_on_terminate
      @close_on_terminate = true
    end

  private
    def terminate
      if @close_on_terminate
        @dev.close
      end
    end
  end

  # SYNOPSIS
  #   cells = CSV.parse_line(src, col_sep = ?,, row_sep = nil)
  #
  # ARGS
  #   src: a CSV String.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   cells: an Array of parsed cells in first line.  Each cell is a String.
  #
  # DESCRIPTION
  #   Parse one line from given string.  Bare in mind it parses ONE LINE.  Rest
  #   of the string is ignored for example "a,b\r\nc,d" => ['a', 'b'] and the
  #   second line 'c,d' is ignored.
  #
  #   If you don't know whether a target string to parse is exactly 1 line or
  #   not, use CSV.parse_row instead of this method.
  #   
  def CSV.parse_line(src, col_sep = ?,, row_sep = nil)
    idx = 0
    res_type = :DT_COLSEP
    cells = Row.new
    begin
      while (res_type.equal?(:DT_COLSEP))
        cell = Cell.new
        res_type, idx = parse_body(src, idx, cell, col_sep, row_sep)
        cells.push(cell.is_null ? nil : cell.data)
      end
    rescue IllegalFormatError
      return Row.new
    end
    cells
  end
  

  # SYNOPSIS
  #   str = CSV.generate_line(cells, col_sep = ?,, row_sep = nil)
  #
  # ARGS
  #   cells: an Array of cell to be converted to CSV string.  Each cell must 
  #     respond to 'to_s'.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   str: a String of generated CSV string.
  #
  # DESCRIPTION
  #   Create a line from cells.  Each cell is stringified by to_s.
  #   
  def CSV.generate_line(cells, col_sep = ?,, row_sep = nil)
    if (cells.size == 0)
      return ''
    end
    res_type = :DT_COLSEP
    result_str = ''
    idx = 0
    while true
      cell = if (cells[idx].nil?)
          Cell.new('', true)
        else
          Cell.new(cells[idx].to_s, false)
        end
      generate_body(cell, result_str, col_sep, row_sep)
      idx += 1
      if (idx == cells.size)
        break
      end
      generate_separator(:DT_COLSEP, result_str, col_sep, row_sep)
    end
    result_str
  end
  
  # SYNOPSIS
  #   parsed_cells, idx = CSV.parse_row(src, idx, out_dev, col_sep = ?,, row_sep = nil)
  #
  # ARGS
  #   src: a CSV data to be parsed.  Must respond '[](idx)'.
  #     src[](idx) must return a char. (Not a string such as 'a', but 97).
  #     src[](idx_out_of_bounds) must return nil.  A String satisfies this
  #     requirement.
  #   idx: index of parsing location of 'src'.  0 origin.
  #   out_dev: buffer for parsed cells.  Must respond '<<(CSV::Cell)'.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   parsed_cells: num of parsed cells.
  #   idx: index of next parsing location of 'src'.
  #
  # DESCRIPTION
  #   Parse a line from string.  To parse lines in CSV string, see EXAMPLE
  #   below.
  #
  # EXAMPLE
  #   src = "a,b\r\nc,d\r\ne,f"
  #   idx = 0
  #   begin
  #     parsed = []
  #     parsed_cells, idx = CSV.parse_row(src, idx, parsed)
  #     puts "Parsed #{ parsed_cells } cells."
  #     p parsed
  #   end while parsed_cells > 0
  #   
  def CSV.parse_row(src, idx, out_dev, col_sep = ?,, row_sep = nil)
    idx_backup = idx
    parsed_cells = 0
    res_type = :DT_COLSEP
    begin
      while (!res_type.equal?(:DT_ROWSEP))
        cell = Cell.new
        res_type, idx = parse_body(src, idx, cell, col_sep, row_sep)
        if res_type.equal?(:DT_EOS)
          if idx == idx_backup #((parsed_cells == 0) && (cell.is_null))
            return 0, 0
          end
          res_type = :DT_ROWSEP
        end
        parsed_cells += 1
        out_dev << cell
      end
    rescue IllegalFormatError
      return 0, 0
    end
    return parsed_cells, idx
  end
  
  # SYNOPSIS
  #   parsed_cells = CSV.generate_row(src, cells, out_dev, col_sep = ?,, row_sep = nil)
  #
  # ARGS
  #   src: an Array of CSV::Cell to be converted to CSV string.  Must respond to
  #     'size' and '[](idx)'.  src[idx] must return CSV::Cell.
  #   cells: num of cells in a line.
  #   out_dev: buffer for generated CSV string.  Must respond to '<<(string)'.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   parsed_cells: num of converted cells.
  #
  # DESCRIPTION
  #   Convert a line from cells data to string.  To generate multi-row CSV
  #   string,  See EXAMPLE below.
  #
  # EXAMPLE
  #   def d(str)
  #     CSV::Cell.new(str, false)
  #   end
  #
  #   row1 = [d('a'), d('b')]
  #   row2 = [d('c'), d('d')]
  #   row3 = [d('e'), d('f')]
  #   src = [row1, row2, row3]
  #   buf = ''
  #   src.each do |row|
  #     parsed_cells = CSV.generate_row(row, 2, buf)
  #     puts "Created #{ parsed_cells } cells."
  #   end
  #   p buf
  #   
  def CSV.generate_row(src, cells, out_dev, col_sep = ?,, row_sep = nil)
    src_size = src.size
    if (src_size == 0)
      if cells == 0
        generate_separator(:DT_ROWSEP, out_dev, col_sep, row_sep)
      end
      return 0
    end
    res_type = :DT_COLSEP
    parsed_cells = 0
    generate_body(src[parsed_cells], out_dev, col_sep, row_sep)
    parsed_cells += 1
    while ((parsed_cells < cells) && (parsed_cells != src_size))
      generate_separator(:DT_COLSEP, out_dev, col_sep, row_sep)
      generate_body(src[parsed_cells], out_dev, col_sep, row_sep)
      parsed_cells += 1
    end
    if (parsed_cells == cells)
      generate_separator(:DT_ROWSEP, out_dev, col_sep, row_sep)
    else
      generate_separator(:DT_COLSEP, out_dev, col_sep, row_sep)
    end
    parsed_cells
  end
  
private
  class IllegalFormatError < RuntimeError; end

  # Private class methods.
  class << self
  private

    def parse_body(src, idx, cell, col_sep, row_sep)
      row_sep_end = row_sep || ?\n
      cell.is_null = false
      state = :ST_START
      quoted = false
      cr = false
      c = nil
      while (c = src[idx])
        idx += 1
        result_state = :DT_UNKNOWN
        if (c == col_sep)
          if state.equal?(:ST_DATA)
            if cr
              raise IllegalFormatError.new
            end
            if (!quoted)
              state = :ST_END
              result_state = :DT_COLSEP
            else
              cell.data << c.chr
            end
          elsif state.equal?(:ST_QUOTE)
            if cr
              raise IllegalFormatError.new
            end
            state = :ST_END
            result_state = :DT_COLSEP
          else  # :ST_START
            cell.is_null = true
            state = :ST_END
            result_state = :DT_COLSEP
          end
        elsif (c == ?")         # " for vim syntax hilighting.
          if state.equal?(:ST_DATA)
            if cr
              raise IllegalFormatError.new
            end
            if quoted
              quoted = false
              state = :ST_QUOTE
            else
              raise IllegalFormatError.new
            end
          elsif state.equal?(:ST_QUOTE)
            cell.data << c.chr
            quoted = true
            state = :ST_DATA
          else  # :ST_START
            quoted = true
            state = :ST_DATA
          end
        elsif row_sep.nil? and c == ?\r
          if cr
            raise IllegalFormatError.new
          end
          if quoted
            cell.data << c.chr
            state = :ST_DATA
          else
            cr = true
          end
        elsif c == row_sep_end
          if state.equal?(:ST_DATA)
            if cr
              state = :ST_END
              result_state = :DT_ROWSEP
              cr = false
            else
              if quoted
                cell.data << c.chr
                state = :ST_DATA
              else
                state = :ST_END
                result_state = :DT_ROWSEP
              end
            end
          elsif state.equal?(:ST_QUOTE)
            state = :ST_END
            result_state = :DT_ROWSEP
            if cr
              cr = false
            end
          else  # :ST_START
            cell.is_null = true
            state = :ST_END
            result_state = :DT_ROWSEP
          end
        else
          if state.equal?(:ST_DATA) || state.equal?(:ST_START)
            if cr
              raise IllegalFormatError.new
            end
            cell.data << c.chr
            state = :ST_DATA
          else  # :ST_QUOTE
            raise IllegalFormatError.new
          end
        end
        if state.equal?(:ST_END)
          return result_state, idx;
        end
      end
      if state.equal?(:ST_START)
        cell.is_null = true
      elsif state.equal?(:ST_QUOTE)
        true    # dummy for coverate; only a data
      elsif quoted
        raise IllegalFormatError.new
      elsif cr
        raise IllegalFormatError.new
      end
      return :DT_EOS, idx
    end
  
    def generate_body(cells, out_dev, col_sep, row_sep)
      row_data = cells.data.dup
      if (!cells.is_null)
        if (row_data.gsub!('"', '""') ||
            row_data.include?(col_sep) ||
	    (row_sep && row_data.index(row_sep)) ||
	    (/[\r\n]/ =~ row_data) ||
	    (cells.data.empty?))
          out_dev << '"' << row_data << '"'
        else
          out_dev << row_data
        end
      end
    end
    
    def generate_separator(type, out_dev, col_sep, row_sep)
      case type
      when :DT_COLSEP
        out_dev << col_sep.chr
      when :DT_ROWSEP
        out_dev << (row_sep ? row_sep.chr : "\r\n")
      end
    end
  end


  # DESCRIPTION
  #   CSV::StreamBuf -- a class for a bufferd stream.
  #
  # EXAMPLE 1 -- an IO.
  #   class MyBuf < StreamBuf
  #     # Do initialize myself before a super class.  Super class might call my
  #     # method 'read'. (Could be awful for C++ user. :-)
  #     def initialize(s)
  #       @s = s
  #       super()
  #     end
  #
  #     # define my own 'read' method.
  #     # CAUTION: Returning nil means EnfOfStream.
  #     def read(size)
  #       @s.read(size)
  #     end
  #
  #     # release buffers. in Ruby which has GC, you do not have to call this...
  #     def terminate
  #       @s = nil
  #       super()
  #     end
  #   end
  #
  #   buf = MyBuf.new(STDIN)
  #   my_str = ''
  #   p buf[0, 0]               # => '' (null string)
  #   p buf[0]                  # => 97 (char code of 'a')
  #   p buf[0, 1]               # => 'a'
  #   my_str = buf[0, 5]
  #   p my_str                  # => 'abcde' (5 chars)
  #   p buf[0, 6]               # => "abcde\n" (6 chars)
  #   p buf[0, 7]               # => "abcde\n" (6 chars)
  #   p buf.drop(3)             # => 3 (dropped chars)
  #   p buf.get(0, 2)           # => 'de' (2 chars)
  #   p buf.is_eos?             # => false (is not EOS here)
  #   p buf.drop(5)             # => 3 (dropped chars)
  #   p buf.is_eos?             # => true (is EOS here)
  #   p buf[0]                  # => nil (is EOS here)
  #
  # EXAMPLE 2 -- String.
  #   This is a conceptual example.  No pros with this.
  # 
  #   class StrBuf < StreamBuf
  #     def initialize(s)
  #       @str = s
  #       @idx = 0
  #       super()
  #     end
  #   
  #     def read(size)
  #       str = @str[@idx, size]
  #       @idx += str.size
  #       str
  #     end
  #   end
  #
  class StreamBuf       # pure virtual. (do not instanciate it directly)
  public
  
    # SYNOPSIS
    #   char/str = CSV::StreamBuf#get(idx, n = nil)
    #   char/str = CSV::StreamBuf#[idx, n = nil]
    #
    # ARGS
    #   idx: index of a string to specify a start point of a string to get.
    #     Unlike String instance, idx < 0 returns nil.
    #   n: size of a string to get.
    #
    # RETURNS
    #   char: if n == nil.  A char at idx.
    #   str: if n != nil.  A partial string, from idx to (idx + size).  At
    #     EOF, the string size could not equal to arg n.
    #
    # DESCRIPTION
    #   Get a char or a partial string from the stream.
    #
    def [](idx, n = nil) 
      if idx < 0
        return nil
      end
      if (idx_is_eos?(idx))
        if n and (@offset + idx == buf_size(@cur_buf))
          # Like a String, 'abc'[4, 1] returns nil and
          # 'abc'[3, 1] returns '' not nil.
          return ''
        else
          return nil
        end
      end
      my_buf = @cur_buf
      my_offset = @offset
      next_idx = idx
      while (my_offset + next_idx >= buf_size(my_buf))
        if (my_buf == @buf_tail_idx)
          unless add_buf
            break
          end
        end
        next_idx = my_offset + next_idx - buf_size(my_buf)
        my_buf += 1
        my_offset = 0
      end
      loc = my_offset + next_idx
      if !n
        return @buf_list[my_buf][loc]		# Fixnum of char code.
      elsif (loc + n - 1 < buf_size(my_buf))
        return @buf_list[my_buf][loc, n]	# String.
      else # should do loop insted of (tail) recursive call...
	res = @buf_list[my_buf][loc, BufSize]
        size_added = buf_size(my_buf) - loc
        if size_added > 0
          idx += size_added
          n -= size_added
          ret = self[idx, n]
          if ret
            res << ret
          end
        end
        return res
      end
    end
    alias get []
  
    # SYNOPSIS
    #   size_dropped = CSV::StreamBuf#drop(n)
    #
    # ARGS
    #   n: drop size
    #
    # RETURNS
    #   size_dropped: droped size.  At EOF, dropped size might not equals to arg n.
    #     0 if n <= 0.
    #
    # DESCRIPTION
    #   Drop a string from the stream.  Once you drop the head of the stream,
    #   access to the dropped part via [] or get returns nil.
    #
    def drop(n)
      if is_eos?
        return 0
      end
      size_dropped = 0
      while (n > 0)
        if (!@is_eos || (@cur_buf != @buf_tail_idx))
          if (@offset + n < buf_size(@cur_buf))
            size_dropped += n
            @offset += n
            n = 0
          else
            size = buf_size(@cur_buf) - @offset
            size_dropped += size
            n -= size
            @offset = 0
            unless rel_buf
              unless add_buf
                break
              end
              @cur_buf = @buf_tail_idx
            end
          end
        end
      end
      size_dropped
    end
  
    # SYNOPSIS
    #   is_eos = CSV::StreamBuf#is_eos?
    #
    # RETURNS
    #   is_eos: true if end of the stream or false.
    #
    # DESCRIPTION
    #   Check EOF or not.
    #
    def is_eos?
      return idx_is_eos?(0)
    end
  
    # SYNOPSIS
    #   N/A
    #
    # DESCRIPTION
    #   Do not instanciate this class directly.  Define your own class which
    #   derives this class and define 'read' instance method.
    #
    def initialize
      @buf_list = []
      @cur_buf = @buf_tail_idx = -1
      @offset = 0
      @is_eos = false
      add_buf
      @cur_buf = @buf_tail_idx
    end
  
  protected
    def terminate
      while (rel_buf); end
    end
  
    # protected method 'read' must be defined in derived classes.
    # CAUTION: Returning a string which size is not equal to 'size' means
    #   EnfOfStream.  When it is not at EOS, you must block the callee, try to
    #   read and return the sized string.
    def read(size) # raise EOFError
      raise NotImplementedError.new('Method read must be defined in a derived class.')
    end
  
  private
  
    def buf_size(idx)
      @buf_list[idx].size
    end

    def add_buf
      if @is_eos
        return false
      end
      begin
        str_read = read(BufSize)
      rescue EOFError
        str_read = nil
      rescue
        terminate
        raise
      end
      if str_read.nil?
        @is_eos = true
        @buf_list.push('')
        @buf_tail_idx += 1
        false
      else
        @buf_list.push(str_read)
        @buf_tail_idx += 1
        true
      end
    end
  
    def rel_buf
      if (@cur_buf < 0)
        return false
      end
      @buf_list[@cur_buf] = nil
      if (@cur_buf == @buf_tail_idx)
        @cur_buf = -1
        return false
      else
        @cur_buf += 1
        return true
      end
    end
  
    def idx_is_eos?(idx)
      (@is_eos && ((@cur_buf < 0) || (@cur_buf == @buf_tail_idx)))
    end
  
    BufSize = 1024 * 8
  end

  # DESCRIPTION
  #   CSV::IOBuf -- a class for a bufferd IO.
  #
  # EXAMPLE
  #   # File 'bigdata' could be a giga-byte size one!
  #   buf = CSV::IOBuf.new(File.open('bigdata', 'rb'))
  #   CSV::Reader.new(buf).each do |row|
  #     p row
  #     break if row[0].data == 'admin'
  #   end
  #
  class IOBuf < StreamBuf
  public
    def initialize(s)
      @s = s
      super()
    end
  
    def close
      terminate
    end

  private
    def read(size)
      @s.read(size)
    end
 
    def terminate
      super()
    end
  end
end
