# CSV -- module for generating/parsing CSV data.
# Copyright (C) 2000-2004  NAKAMURA, Hiroshi <nakahiro@sarion.co.jp>.
  
# $Id$
  
# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.
  
  
class CSV
  class IllegalFormatError < RuntimeError; end

  # deprecated
  class Cell < String
    def initialize(data = "", is_null = false)
      super(is_null ? "" : data)
    end

    def data
      to_s
    end
  end

  # deprecated
  class Row < Array
  end

  # Open a CSV formatted file for reading or writing.
  #
  # For reading.
  #
  # EXAMPLE 1
  #   CSV.open('csvfile.csv', 'r') do |row|
  #     p row
  #   end
  #
  # EXAMPLE 2
  #   reader = CSV.open('csvfile.csv', 'r')
  #   row1 = reader.shift
  #   row2 = reader.shift
  #   if row2.empty?
  #     p 'row2 not find.'
  #   end
  #   reader.close
  #
  # ARGS
  #   filename: filename to parse.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   reader instance.  To get parse result, see CSV::Reader#each.
  #
  #
  # For writing.
  #
  # EXAMPLE 1
  #   CSV.open('csvfile.csv', 'w') do |writer|
  #     writer << ['r1c1', 'r1c2']
  #     writer << ['r2c1', 'r2c2']
  #     writer << [nil, nil]
  #   end
  #
  # EXAMPLE 2
  #   writer = CSV.open('csvfile.csv', 'w')
  #   writer << ['r1c1', 'r1c2'] << ['r2c1', 'r2c2'] << [nil, nil]
  #   writer.close
  #
  # ARGS
  #   filename: filename to generate.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   writer instance.  See CSV::Writer#<< and CSV::Writer#add_row to know how
  #   to generate CSV string.
  #
  def CSV.open(path, mode, fs = nil, rs = nil, &block)
    if mode == 'r' or mode == 'rb'
      open_reader(path, mode, fs, rs, &block)
    elsif mode == 'w' or mode == 'wb'
      open_writer(path, mode, fs, rs, &block)
    else
      raise ArgumentError.new("'mode' must be 'r', 'rb', 'w', or 'wb'")
    end
  end

  def CSV.foreach(path, rs = nil, &block)
    open_reader(path, 'r', ',', rs, &block)
  end

  def CSV.read(path, length = nil, offset = nil)
    CSV.parse(IO.read(path, length, offset))
  end
  
  def CSV.readlines(path, rs = nil)
    reader = open_reader(path, 'r', ',', rs)
    begin
      reader.collect { |row| row }
    ensure
      reader.close
    end
  end

  def CSV.generate(path, fs = nil, rs = nil, &block)
    open_writer(path, 'w', fs, rs, &block)
  end

  # Parse lines from given string or stream.  Return rows as an Array of Arrays.
  def CSV.parse(str_or_readable, fs = nil, rs = nil, &block)
    if File.exist?(str_or_readable)
      STDERR.puts("CSV.parse(filename) is deprecated." +
        "  Use CSV.open(filename, 'r') instead.")
      return open_reader(str_or_readable, 'r', fs, rs, &block)
    end
    if block
      CSV::Reader.parse(str_or_readable, fs, rs) do |row|
        yield(row)
      end
      nil
    else
      CSV::Reader.create(str_or_readable, fs, rs).collect { |row| row }
    end
  end

  # Parse a line from given string.  Bear in mind it parses ONE LINE.  Rest of
  # the string is ignored for example "a,b\r\nc,d" => ['a', 'b'] and the
  # second line 'c,d' is ignored.
  #
  # If you don't know whether a target string to parse is exactly 1 line or
  # not, use CSV.parse_row instead of this method.
  def CSV.parse_line(src, fs = nil, rs = nil)
    fs ||= ','
    if fs.is_a?(Fixnum)
      fs = fs.chr
    end
    if !rs.nil? and rs.is_a?(Fixnum)
      rs = rs.chr
    end
    idx = 0
    res_type = :DT_COLSEP
    row = []
    begin
      while res_type == :DT_COLSEP
        res_type, idx, cell = parse_body(src, idx, fs, rs)
        row << cell
      end
    rescue IllegalFormatError
      return []
    end
    row
  end

  # Create a line from cells.  each cell is stringified by to_s.
  def CSV.generate_line(row, fs = nil, rs = nil)
    if row.size == 0
      return ''
    end
    fs ||= ','
    if fs.is_a?(Fixnum)
      fs = fs.chr
    end
    if !rs.nil? and rs.is_a?(Fixnum)
      rs = rs.chr
    end
    res_type = :DT_COLSEP
    result_str = ''
    idx = 0
    while true
      generate_body(row[idx], result_str, fs, rs)
      idx += 1
      if (idx == row.size)
        break
      end
      generate_separator(:DT_COLSEP, result_str, fs, rs)
    end
    result_str
  end
  
  # Parse a line from string.  Consider using CSV.parse_line instead.
  # To parse lines in CSV string, see EXAMPLE below.
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
  # ARGS
  #   src: a CSV data to be parsed.  Must respond '[](idx)'.
  #     src[](idx) must return a char. (Not a string such as 'a', but 97).
  #     src[](idx_out_of_bounds) must return nil.  A String satisfies this
  #     requirement.
  #   idx: index of parsing location of 'src'.  0 origin.
  #   out_dev: buffer for parsed cells.  Must respond '<<(aString)'.
  #   col_sep: Column separator.  ?, by default.  If you want to separate
  #     fields with semicolon, give ?; here.
  #   row_sep: Row separator.  nil by default.  nil means "\r\n or \n".  If you
  #     want to separate records with \r, give ?\r here.
  #
  # RETURNS
  #   parsed_cells: num of parsed cells.
  #   idx: index of next parsing location of 'src'.
  #
  def CSV.parse_row(src, idx, out_dev, fs = nil, rs = nil)
    fs ||= ','
    if fs.is_a?(Fixnum)
      fs = fs.chr
    end
    if !rs.nil? and rs.is_a?(Fixnum)
      rs = rs.chr
    end
    idx_backup = idx
    parsed_cells = 0
    res_type = :DT_COLSEP
    begin
      while res_type != :DT_ROWSEP
        res_type, idx, cell = parse_body(src, idx, fs, rs)
        if res_type == :DT_EOS
          if idx == idx_backup #((parsed_cells == 0) and cell.nil?)
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
  
  # Convert a line from cells data to string.  Consider using CSV.generate_line
  # instead.  To generate multi-row CSV string, see EXAMPLE below.
  #
  # EXAMPLE
  #   row1 = ['a', 'b']
  #   row2 = ['c', 'd']
  #   row3 = ['e', 'f']
  #   src = [row1, row2, row3]
  #   buf = ''
  #   src.each do |row|
  #     parsed_cells = CSV.generate_row(row, 2, buf)
  #     puts "Created #{ parsed_cells } cells."
  #   end
  #   p buf
  #
  # ARGS
  #   src: an Array of String to be converted to CSV string.  Must respond to
  #     'size' and '[](idx)'.  src[idx] must return String.
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
  def CSV.generate_row(src, cells, out_dev, fs = nil, rs = nil)
    fs ||= ','
    if fs.is_a?(Fixnum)
      fs = fs.chr
    end
    if !rs.nil? and rs.is_a?(Fixnum)
      rs = rs.chr
    end
    src_size = src.size
    if (src_size == 0)
      if cells == 0
        generate_separator(:DT_ROWSEP, out_dev, fs, rs)
      end
      return 0
    end
    res_type = :DT_COLSEP
    parsed_cells = 0
    generate_body(src[parsed_cells], out_dev, fs, rs)
    parsed_cells += 1
    while ((parsed_cells < cells) and (parsed_cells != src_size))
      generate_separator(:DT_COLSEP, out_dev, fs, rs)
      generate_body(src[parsed_cells], out_dev, fs, rs)
      parsed_cells += 1
    end
    if (parsed_cells == cells)
      generate_separator(:DT_ROWSEP, out_dev, fs, rs)
    else
      generate_separator(:DT_COLSEP, out_dev, fs, rs)
    end
    parsed_cells
  end
  
  # Private class methods.
  class << self
  private

    def open_reader(path, mode, fs, rs, &block)
      file = File.open(path, mode)
      if block
        begin
          CSV::Reader.parse(file, fs, rs) do |row|
            yield(row)
          end
        ensure
          file.close
        end
        nil
      else
        reader = CSV::Reader.create(file, fs, rs)
        reader.close_on_terminate
        reader
      end
    end

    def open_writer(path, mode, fs, rs, &block)
      file = File.open(path, mode)
      if block
        begin
          CSV::Writer.generate(file, fs, rs) do |writer|
            yield(writer)
          end
        ensure
          file.close
        end
        nil
      else
        writer = CSV::Writer.create(file, fs, rs) 
        writer.close_on_terminate
        writer
      end
    end

    def parse_body(src, idx, fs, rs)
      fs_str = fs
      fs_size = fs_str.size
      rs_str = rs || "\n"
      rs_size = rs_str.size
      fs_idx = rs_idx = 0
      cell = Cell.new
      state = :ST_START
      quoted = cr = false
      c = nil
      last_idx = idx
      while c = src[idx]
        unless quoted
          fschar = (c == fs_str[fs_idx])
          rschar = (c == rs_str[rs_idx])
          # simple 1 char backtrack
          if !fschar and c == fs_str[0]
            fs_idx = 0
            fschar = true
            if state == :ST_START
              state = :ST_DATA
            elsif state == :ST_QUOTE
              raise IllegalFormatError
            end
          end
          if !rschar and c == rs_str[0]
            rs_idx = 0
            rschar = true
            if state == :ST_START
              state = :ST_DATA
            elsif state == :ST_QUOTE
              raise IllegalFormatError
            end
          end
        end
        if c == ?"
          fs_idx = rs_idx = 0
          if cr
            raise IllegalFormatError
          end
          cell << src[last_idx, (idx - last_idx)]
          last_idx = idx
          if state == :ST_DATA
            if quoted
              last_idx += 1
              quoted = false
              state = :ST_QUOTE
            else
              raise IllegalFormatError
            end
          elsif state == :ST_QUOTE
            cell << c.chr
            last_idx += 1
            quoted = true
            state = :ST_DATA
          else  # :ST_START
            quoted = true
            last_idx += 1
            state = :ST_DATA
          end
        elsif fschar or rschar
          if fschar
            fs_idx += 1
          end
          if rschar
            rs_idx += 1
          end
          sep = nil
          if fs_idx == fs_size
            if state == :ST_START and rs_idx > 0 and fs_idx < rs_idx
              state = :ST_DATA
            end
            cell << src[last_idx, (idx - last_idx - (fs_size - 1))]
            last_idx = idx
            fs_idx = rs_idx = 0
            if cr
              raise IllegalFormatError
            end
            sep = :DT_COLSEP
          elsif rs_idx == rs_size
            if state == :ST_START and fs_idx > 0 and rs_idx < fs_idx
              state = :ST_DATA
            end
            if !(rs.nil? and cr)
              cell << src[last_idx, (idx - last_idx - (rs_size - 1))]
              last_idx = idx
            end
            fs_idx = rs_idx = 0
            sep = :DT_ROWSEP
          end
          if sep
            if state == :ST_DATA
              return sep, idx + 1, cell;
            elsif state == :ST_QUOTE
              return sep, idx + 1, cell;
            else  # :ST_START
              return sep, idx + 1, nil
            end
          end
        elsif rs.nil? and c == ?\r
          # special \r treatment for backward compatibility
          fs_idx = rs_idx = 0
          if cr
            raise IllegalFormatError
          end
          cell << src[last_idx, (idx - last_idx)]
          last_idx = idx
          if quoted
            state = :ST_DATA
          else
            cr = true
          end
        else
          fs_idx = rs_idx = 0
          if state == :ST_DATA or state == :ST_START
            if cr
              raise IllegalFormatError
            end
            state = :ST_DATA
          else  # :ST_QUOTE
            raise IllegalFormatError
          end
        end
        idx += 1
      end
      if state == :ST_START
        if fs_idx > 0 or rs_idx > 0
          state = :ST_DATA
        else
          return :DT_EOS, idx, nil
        end
      elsif quoted
        raise IllegalFormatError
      elsif cr
        raise IllegalFormatError
      end
      cell << src[last_idx, (idx - last_idx)]
      last_idx = idx
      return :DT_EOS, idx, cell
    end
  
    def generate_body(cell, out_dev, fs, rs)
      if cell.nil?
        # empty
      else
        cell = cell.to_s
        row_data = cell.dup
        if (row_data.gsub!('"', '""') or
            row_data.index(fs) or
            (rs and row_data.index(rs)) or
            (/[\r\n]/ =~ row_data) or
            (cell.empty?))
          out_dev << '"' << row_data << '"'
        else
          out_dev << row_data
        end
      end
    end
    
    def generate_separator(type, out_dev, fs, rs)
      case type
      when :DT_COLSEP
        out_dev << fs
      when :DT_ROWSEP
        out_dev << (rs || "\n")
      end
    end
  end


  # CSV formatted string/stream reader.
  #
  # EXAMPLE
  #   read CSV lines untill the first column is 'stop'.
  #
  #   CSV::Reader.parse(File.open('bigdata', 'rb')) do |row|
  #     p row
  #     break if !row[0].is_null && row[0].data == 'stop'
  #   end
  #
  class Reader
    include Enumerable

    # Parse CSV data and get lines.  Given block is called for each parsed row.
    # Block value is always nil.  Rows are not cached for performance reason.
    def Reader.parse(str_or_readable, fs = ',', rs = nil, &block)
      reader = Reader.create(str_or_readable, fs, rs)
      if block
        reader.each do |row|
          yield(row)
        end
        reader.close
        nil
      else
        reader
      end
    end

    # Returns reader instance.
    def Reader.create(str_or_readable, fs = ',', rs = nil)
      case str_or_readable
      when IO
        IOReader.new(str_or_readable, fs, rs)
      when String
        StringReader.new(str_or_readable, fs, rs)
      else
        IOReader.new(str_or_readable, fs, rs)
      end
    end

    def each
      while true
        row = []
        parsed_cells = get_row(row)
        if parsed_cells == 0
          break
        end
        yield(row)
      end
      nil
    end

    def shift
      row = []
      parsed_cells = get_row(row)
      row
    end

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
  

  class StringReader < Reader
    def initialize(string, fs = ',', rs = nil)
      @fs = fs
      @rs = rs
      @dev = string
      @idx = 0
      if @dev[0, 3] == "\xef\xbb\xbf"
        @idx += 3
      end
    end

  private

    def get_row(row)
      parsed_cells, next_idx = CSV.parse_row(@dev, @idx, row, @fs, @rs)
      if parsed_cells == 0 and next_idx == 0 and @idx != @dev.size
        raise IllegalFormatError.new
      end
      @idx = next_idx
      parsed_cells
    end
  end


  class IOReader < Reader
    def initialize(io, fs = ',', rs = nil)
      @io = io
      @fs = fs
      @rs = rs
      @dev = CSV::IOBuf.new(@io)
      @idx = 0
      if @dev[0] == 0xef and @dev[1] == 0xbb and @dev[2] == 0xbf
        @idx += 3
      end
      @close_on_terminate = false
    end

    # Tell this reader to close the IO when terminated (Triggered by invoking
    # CSV::IOReader#close).
    def close_on_terminate
      @close_on_terminate = true
    end

  private

    def get_row(row)
      parsed_cells, next_idx = CSV.parse_row(@dev, @idx, row, @fs, @rs)
      if parsed_cells == 0 and next_idx == 0 and !@dev.is_eos?
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


  # CSV formatted string/stream writer.
  #
  # EXAMPLE
  #   Write rows to 'csvout' file.
  #
  #   outfile = File.open('csvout', 'wb')
  #   CSV::Writer.generate(outfile) do |csv|
  #     csv << ['c1', nil, '', '"', "\r\n", 'c2']
  #     ...
  #   end
  #
  #   outfile.close
  #
  class Writer
    # Given block is called with the writer instance.  str_or_writable must
    # handle '<<(string)'.
    def Writer.generate(str_or_writable, fs = ',', rs = nil, &block)
      writer = Writer.create(str_or_writable, fs, rs)
      if block
        yield(writer)
        writer.close
        nil
      else
        writer
      end
    end

    # str_or_writable must handle '<<(string)'.
    def Writer.create(str_or_writable, fs = ',', rs = nil)
      BasicWriter.new(str_or_writable, fs, rs)
    end

    # dump CSV stream to the device.  argument must be an Array of String.
    def <<(row)
      CSV.generate_row(row, row.size, @dev, @fs, @rs)
      self
    end
    alias add_row <<

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


  class BasicWriter < Writer
    def initialize(str_or_writable, fs = ',', rs = nil)
      @fs = fs
      @rs = rs
      @dev = str_or_writable
      @close_on_terminate = false
    end

    # Tell this writer to close the IO when terminated (Triggered by invoking
    # CSV::BasicWriter#close).
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

private

  # Buffered stream.
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
  class StreamBuf
    # get a char or a partial string from the stream.
    # idx: index of a string to specify a start point of a string to get.
    # unlike String instance, idx < 0 returns nil.
    # n: size of a string to get.
    # returns char at idx if n == nil.
    # returns a partial string, from idx to (idx + n) if n != nil.  at EOF,
    # the string size could not equal to arg n.
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
        return @buf_list[my_buf][loc]           # Fixnum of char code.
      elsif (loc + n - 1 < buf_size(my_buf))
        return @buf_list[my_buf][loc, n]        # String.
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
  
    # drop a string from the stream.
    # returns dropped size.  at EOF, dropped size might not equals to arg n.
    # Once you drop the head of the stream, access to the dropped part via []
    # or get returns nil.
    def drop(n)
      if is_eos?
        return 0
      end
      size_dropped = 0
      while (n > 0)
        if !@is_eos or (@cur_buf != @buf_tail_idx)
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
  
    def is_eos?
      return idx_is_eos?(0)
    end
  
    # WARN: Do not instantiate this class directly.  Define your own class
    # which derives this class and define 'read' instance method.
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
    # EnfOfStream.  When it is not at EOS, you must block the callee, try to
    # read and return the sized string.
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
      (@is_eos and ((@cur_buf < 0) or (@cur_buf == @buf_tail_idx)))
    end
  
    BufSize = 1024 * 8
  end

  # Buffered IO.
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
