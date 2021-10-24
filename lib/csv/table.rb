# frozen_string_literal: true

require "forwardable"

class CSV
  #
  # A CSV::Table is a two-dimensional data structure for representing CSV
  # documents. Tables allow you to work with the data by row or column,
  # manipulate the data, and even convert the results back to CSV, if needed.
  #
  # All tables returned by CSV will be constructed from this class, if header
  # row processing is activated.
  #
  class Table
    #
    # Constructs a new CSV::Table from +array_of_rows+, which are expected
    # to be CSV::Row objects. All rows are assumed to have the same headers.
    #
    # The optional +headers+ parameter can be set to Array of headers.
    # If headers aren't set, headers are fetched from CSV::Row objects.
    # Otherwise, headers() method will return headers being set in
    # headers argument.
    #
    # A CSV::Table object supports the following Array methods through
    # delegation:
    #
    # * empty?()
    # * length()
    # * size()
    #
    def initialize(array_of_rows, headers: nil)
      @table = array_of_rows
      @headers = headers
      unless @headers
        if @table.empty?
          @headers = []
        else
          @headers = @table.first.headers
        end
      end

      @mode  = :col_or_row
    end

    # The current access mode for indexing and iteration.
    attr_reader :mode

    # Internal data format used to compare equality.
    attr_reader :table
    protected   :table

    ### Array Delegation ###

    extend Forwardable
    def_delegators :@table, :empty?, :length, :size

    #
    # Returns a duplicate table object, in column mode. This is handy for
    # chaining in a single call without changing the table mode, but be aware
    # that this method can consume a fair amount of memory for bigger data sets.
    #
    # This method returns the duplicate table for chaining. Don't chain
    # destructive methods (like []=()) this way though, since you are working
    # with a duplicate.
    #
    def by_col
      self.class.new(@table.dup).by_col!
    end

    #
    # Switches the mode of this table to column mode. All calls to indexing and
    # iteration methods will work with columns until the mode is changed again.
    #
    # This method returns the table and is safe to chain.
    #
    def by_col!
      @mode = :col

      self
    end

    #
    # Returns a duplicate table object, in mixed mode. This is handy for
    # chaining in a single call without changing the table mode, but be aware
    # that this method can consume a fair amount of memory for bigger data sets.
    #
    # This method returns the duplicate table for chaining.  Don't chain
    # destructive methods (like []=()) this way though, since you are working
    # with a duplicate.
    #
    def by_col_or_row
      self.class.new(@table.dup).by_col_or_row!
    end

    #
    # Switches the mode of this table to mixed mode. All calls to indexing and
    # iteration methods will use the default intelligent indexing system until
    # the mode is changed again. In mixed mode an index is assumed to be a row
    # reference while anything else is assumed to be column access by headers.
    #
    # This method returns the table and is safe to chain.
    #
    def by_col_or_row!
      @mode = :col_or_row

      self
    end

    #
    # Returns a duplicate table object, in row mode.  This is handy for chaining
    # in a single call without changing the table mode, but be aware that this
    # method can consume a fair amount of memory for bigger data sets.
    #
    # This method returns the duplicate table for chaining.  Don't chain
    # destructive methods (like []=()) this way though, since you are working
    # with a duplicate.
    #
    def by_row
      self.class.new(@table.dup).by_row!
    end

    #
    # Switches the mode of this table to row mode. All calls to indexing and
    # iteration methods will work with rows until the mode is changed again.
    #
    # This method returns the table and is safe to chain.
    #
    def by_row!
      @mode = :row

      self
    end

    #
    # Returns the headers for the first row of this table (assumed to match all
    # other rows). The headers Array passed to CSV::Table.new is returned for
    # empty tables.
    #
    def headers
      if @table.empty?
        @headers.dup
      else
        @table.first.headers
      end
    end

    # :call-seq:
    #   table[n] -> row
    #   table[range] -> array_of_rows
    #   table[header] -> array_of_fields
    #
    # Returns data from the table;  does not modify the table.
    #
    # ---
    #
    # The expression <tt>table[n]</tt>, where +n+ is a non-negative \Integer,
    # returns the +n+th row of the table, if that row exists,
    # and if the access mode is <tt>:row</tt> or <tt>:col_or_row</tt>:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.by_row! # => #<CSV::Table mode:row row_count:4>
    #   table[1] # => #<CSV::Row "Name":"bar" "Value":"1">
    #   table.by_col_or_row! # => #<CSV::Table mode:col_or_row row_count:4>
    #   table[1] # => #<CSV::Row "Name":"bar" "Value":"1">
    #
    # Counts backward from the last row if +n+ is negative:
    #   table[-1] # => #<CSV::Row "Name":"baz" "Value":"2">
    #
    # Returns +nil+ if +n+ is too large or too small:
    #   table[4] # => nil
    #   table[-4] => nil
    #
    # Raises an exception if the access mode is <tt>:row</tt>
    # and +n+ is not an
    # {Integer-convertible object}[https://docs.ruby-lang.org/en/master/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
    #   table.by_row! # => #<CSV::Table mode:row row_count:4>
    #   # Raises TypeError (no implicit conversion of String into Integer):
    #   table['Name']
    #
    # ---
    #
    # The expression <tt>table[range]</tt>, where +range+ is a Range object,
    # returns rows from the table, beginning at row <tt>range.first</tt>,
    # if those rows exist, and if the access mode is <tt>:row</tt> or <tt>:col_or_row</tt>:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.by_row! # => #<CSV::Table mode:row row_count:4>
    #   rows = table[1..2] # => #<CSV::Row "Name":"bar" "Value":"1">
    #   rows # => [#<CSV::Row "Name":"bar" "Value":"1">, #<CSV::Row "Name":"baz" "Value":"2">]
    #   table.by_col_or_row! # => #<CSV::Table mode:col_or_row row_count:4>
    #   rows = table[1..2] # => #<CSV::Row "Name":"bar" "Value":"1">
    #   rows # => [#<CSV::Row "Name":"bar" "Value":"1">, #<CSV::Row "Name":"baz" "Value":"2">]
    #
    # If there are too few rows, returns all from <tt>range.first</tt> to the end:
    #   rows = table[1..50] # => #<CSV::Row "Name":"bar" "Value":"1">
    #   rows # => [#<CSV::Row "Name":"bar" "Value":"1">, #<CSV::Row "Name":"baz" "Value":"2">]
    #
    # Special case:  if <tt>range.start == table.size</tt>, returns an empty \Array:
    #   table[table.size..50] # => []
    #
    # If <tt>range.end</tt> is negative, calculates the ending index from the end:
    #   rows = table[0..-1]
    #   rows # => [#<CSV::Row "Name":"foo" "Value":"0">, #<CSV::Row "Name":"bar" "Value":"1">, #<CSV::Row "Name":"baz" "Value":"2">]
    #
    # If <tt>range.start</tt> is negative, calculates the starting index from the end:
    #   rows = table[-1..2]
    #   rows # => [#<CSV::Row "Name":"baz" "Value":"2">]
    #
    # If <tt>range.start</tt> is larger than <tt>table.size</tt>, returns +nil+:
    #   table[4..4] # => nil
    #
    # ---
    #
    # The expression <tt>table[header]</tt>, where +header+ is a \String,
    # returns column values (\Array of \Strings) if the column exists
    # and if the access mode is <tt>:col</tt> or <tt>:col_or_row</tt>:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.by_col! # => #<CSV::Table mode:col row_count:4>
    #   table['Name'] # => ["foo", "bar", "baz"]
    #   table.by_col_or_row! # => #<CSV::Table mode:col_or_row row_count:4>
    #   col = table['Name']
    #   col # => ["foo", "bar", "baz"]
    #
    # Modifying the returned column values does not modify the table:
    #   col[0] = 'bat'
    #   col # => ["bat", "bar", "baz"]
    #   table['Name'] # => ["foo", "bar", "baz"]
    #
    # Returns an \Array of +nil+ values if there is no such column:
    #   table['Nosuch'] # => [nil, nil, nil]
    def [](index_or_header)
      if @mode == :row or  # by index
         (@mode == :col_or_row and (index_or_header.is_a?(Integer) or index_or_header.is_a?(Range)))
        @table[index_or_header]
      else                 # by header
        @table.map { |row| row[index_or_header] }
      end
    end

    #
    # In the default mixed mode, this method assigns rows for index access and
    # columns for header access. You can force the index association by first
    # calling by_col!() or by_row!().
    #
    # Rows may be set to an Array of values (which will inherit the table's
    # headers()) or a CSV::Row.
    #
    # Columns may be set to a single value, which is copied to each row of the
    # column, or an Array of values. Arrays of values are assigned to rows top
    # to bottom in row major order. Excess values are ignored and if the Array
    # does not have a value for each row the extra rows will receive a +nil+.
    #
    # Assigning to an existing column or row clobbers the data. Assigning to
    # new columns creates them at the right end of the table.
    #
    def []=(index_or_header, value)
      if @mode == :row or  # by index
         (@mode == :col_or_row and index_or_header.is_a? Integer)
        if value.is_a? Array
          @table[index_or_header] = Row.new(headers, value)
        else
          @table[index_or_header] = value
        end
      else                 # set column
        unless index_or_header.is_a? Integer
          index = @headers.index(index_or_header) || @headers.size
          @headers[index] = index_or_header
        end
        if value.is_a? Array  # multiple values
          @table.each_with_index do |row, i|
            if row.header_row?
              row[index_or_header] = index_or_header
            else
              row[index_or_header] = value[i]
            end
          end
        else                  # repeated value
          @table.each do |row|
            if row.header_row?
              row[index_or_header] = index_or_header
            else
              row[index_or_header] = value
            end
          end
        end
      end
    end

    # :call-seq:
    #   table.values_at(*indexes) -> array_of_rows
    #   table.values_at(*headers) -> array_of_columns_data
    #
    # If the access mode is <tt>:row</tt> or <tt>:col_or_row</tt>,
    # and each argument is either an \Integer or a \Range,
    # returns rows.
    # Otherwise, returns columns data.
    #
    # In either case, the returned values are in the order
    # specified by the arguments.  Arguments may be repeated.
    #
    # ---
    #
    # Returns rows as an \Array of \CSV::Row objects.
    #
    # No argument:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.values_at # => []
    #
    # One index:
    #   values = table.values_at(0)
    #   values # => [#<CSV::Row "Name":"foo" "Value":"0">]
    #
    # Two indexes:
    #   values = table.values_at(2, 0)
    #   values # => [#<CSV::Row "Name":"baz" "Value":"2">, #<CSV::Row "Name":"foo" "Value":"0">]
    #
    # One \Range:
    #   values = table.values_at(1..2)
    #   values # => [#<CSV::Row "Name":"bar" "Value":"1">, #<CSV::Row "Name":"baz" "Value":"2">]
    #
    # \Ranges and indexes:
    #   values = table.values_at(0..1, 1..2, 0, 2)
    #   pp values
    # Output:
    #   [#<CSV::Row "Name":"foo" "Value":"0">,
    #    #<CSV::Row "Name":"bar" "Value":"1">,
    #    #<CSV::Row "Name":"bar" "Value":"1">,
    #    #<CSV::Row "Name":"baz" "Value":"2">,
    #    #<CSV::Row "Name":"foo" "Value":"0">,
    #    #<CSV::Row "Name":"baz" "Value":"2">]
    #
    # ---
    #
    # Returns columns data as row Arrays,
    # each consisting of the specified columns data for that row:
    #   values = table.values_at('Name')
    #   values # => [["foo"], ["bar"], ["baz"]]
    #   values = table.values_at('Value', 'Name')
    #   values # => [["0", "foo"], ["1", "bar"], ["2", "baz"]]
    def values_at(*indices_or_headers)
      if @mode == :row or  # by indices
         ( @mode == :col_or_row and indices_or_headers.all? do |index|
                                      index.is_a?(Integer)         or
                                      ( index.is_a?(Range)         and
                                        index.first.is_a?(Integer) and
                                        index.last.is_a?(Integer) )
                                    end )
        @table.values_at(*indices_or_headers)
      else                 # by headers
        @table.map { |row| row.values_at(*indices_or_headers) }
      end
    end

    # :call-seq:
    #   table << row_or_array -> self
    #
    # If +row_or_array+ is a \CSV::Row object,
    # it is appended to the table:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table << CSV::Row.new(table.headers, ['bat', 3])
    #   table[3] # => #<CSV::Row "Name":"bat" "Value":3>
    #
    # If +row_or_array+ is an \Array, it is used to create a new
    # \CSV::Row object which is then appended to the table:
    #   table << ['bam', 4]
    #   table[4] # => #<CSV::Row "Name":"bam" "Value":4>
    def <<(row_or_array)
      if row_or_array.is_a? Array  # append Array
        @table << Row.new(headers, row_or_array)
      else                         # append Row
        @table << row_or_array
      end

      self # for chaining
    end

    #
    # :call-seq:
    #   table.push(*rows_or_arrays) -> self
    #
    # A shortcut for appending multiple rows. Equivalent to:
    #   rows.each {|row| self << row }
    #
    # Each argument may be either a \CSV::Row object or an \Array:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   rows = [
    #     CSV::Row.new(table.headers, ['bat', 3]),
    #     ['bam', 4]
    #   ]
    #   table.push(*rows)
    #   table[3..4] # => [#<CSV::Row "Name":"bat" "Value":3>, #<CSV::Row "Name":"bam" "Value":4>]
    def push(*rows)
      rows.each { |row| self << row }

      self # for chaining
    end

    # :call-seq:
    #   table.delete(*indexes) -> deleted_values
    #   table.delete(*headers) -> deleted_values
    #
    # If the access mode is <tt>:row</tt> or <tt>:col_or_row</tt>,
    # and each argument is either an \Integer or a \Range,
    # returns deleted rows.
    # Otherwise, returns deleted columns data.
    #
    # In either case, the returned values are in the order
    # specified by the arguments.  Arguments may be repeated.
    #
    # ---
    #
    # Returns rows as an \Array of \CSV::Row objects.
    #
    # One index:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   deleted_values = table.delete(0)
    #   deleted_values # => [#<CSV::Row "Name":"foo" "Value":"0">]
    #
    # Two indexes:
    #   table = CSV.parse(source, headers: true)
    #   deleted_values = table.delete(2, 0)
    #   deleted_values # => [#<CSV::Row "Name":"baz" "Value":"2">, #<CSV::Row "Name":"foo" "Value":"0">]
    #
    # ---
    #
    # Returns columns data as column Arrays.
    #
    # One header:
    #   table = CSV.parse(source, headers: true)
    #   deleted_values = table.delete('Name')
    #   deleted_values # => ["foo", "bar", "baz"]
    #
    # Two headers:
    #   table = CSV.parse(source, headers: true)
    #   deleted_values = table.delete('Value', 'Name')
    #   deleted_values # => [["0", "1", "2"], ["foo", "bar", "baz"]]
    def delete(*indexes_or_headers)
      if indexes_or_headers.empty?
        raise ArgumentError, "wrong number of arguments (given 0, expected 1+)"
      end
      deleted_values = indexes_or_headers.map do |index_or_header|
        if @mode == :row or  # by index
            (@mode == :col_or_row and index_or_header.is_a? Integer)
          @table.delete_at(index_or_header)
        else                 # by header
          if index_or_header.is_a? Integer
            @headers.delete_at(index_or_header)
          else
            @headers.delete(index_or_header)
          end
          @table.map { |row| row.delete(index_or_header).last }
        end
      end
      if indexes_or_headers.size == 1
        deleted_values[0]
      else
        deleted_values
      end
    end

    # Removes rows or columns for which the block returns a truthy value;
    # returns +self+.
    #
    # Removes rows when the access mode is <tt>:row</tt> or <tt>:col_or_row</tt>;
    # calls the block with each \CSV::Row object:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.by_row! # => #<CSV::Table mode:row row_count:4>
    #   table.size # => 3
    #   table.delete_if {|row| row['Name'].start_with?('b') }
    #   table.size # => 1
    #
    # Removes columns when the access mode is <tt>:col</tt>;
    # calls the block with each column as a 2-element array
    # containing the header and an \Array of column fields:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.by_col! # => #<CSV::Table mode:col row_count:4>
    #   table.headers.size # => 2
    #   table.delete_if {|column_data| column_data[1].include?('2') }
    #   table.headers.size # => 1
    #
    # Returns a new \Enumerator if no block is given:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.delete_if # => #<Enumerator: #<CSV::Table mode:col_or_row row_count:4>:delete_if>
    def delete_if(&block)
      return enum_for(__method__) { @mode == :row or @mode == :col_or_row ? size : headers.size } unless block_given?

      if @mode == :row or @mode == :col_or_row  # by index
        @table.delete_if(&block)
      else                                      # by header
        deleted = []
        headers.each do |header|
          deleted << delete(header) if yield([header, self[header]])
        end
      end

      self # for chaining
    end

    include Enumerable

    # Calls the block with each row or column; returns +self+.
    #
    # When the access mode is <tt>:row</tt> or <tt>:col_or_row</tt>,
    # calls the block with each \CSV::Row object:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   table.by_row! # => #<CSV::Table mode:row row_count:4>
    #   table.each {|row| p row }
    # Output:
    #   #<CSV::Row "Name":"foo" "Value":"0">
    #   #<CSV::Row "Name":"bar" "Value":"1">
    #   #<CSV::Row "Name":"baz" "Value":"2">
    #
    # When the access mode is <tt>:col</tt>,
    # calls the block with each column as a 2-element array
    # containing the header and an \Array of column fields:
    #   table.by_col! # => #<CSV::Table mode:col row_count:4>
    #   table.each {|column_data| p column_data }
    # Output:
    #   ["Name", ["foo", "bar", "baz"]]
    #   ["Value", ["0", "1", "2"]]
    #
    # Returns a new \Enumerator if no block is given:
    #   table.each # => #<Enumerator: #<CSV::Table mode:col row_count:4>:each>
    def each(&block)
      return enum_for(__method__) { @mode == :col ? headers.size : size } unless block_given?

      if @mode == :col
        headers.each { |header| yield([header, self[header]]) }
      else
        @table.each(&block)
      end

      self # for chaining
    end

    # Returns +true+ if all each row of +self+ <tt>==</tt>
    # the corresponding row of +other_table+, otherwise, +false+.
    #
    # The access mode does no affect the result.
    #
    # Equal tables:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   other_table = CSV.parse(source, headers: true)
    #   table == other_table # => true
    #
    # Different row count:
    #   other_table.delete(2)
    #   table == other_table # => false
    #
    # Different last row:
    #   other_table << ['bat', 3]
    #   table == other_table # => false
    def ==(other)
      return @table == other.table if other.is_a? CSV::Table
      @table == other
    end

    #
    # Returns the table as an Array of Arrays. Headers will be the first row,
    # then all of the field rows will follow.
    #
    def to_a
      array = [headers]
      @table.each do |row|
        array.push(row.fields) unless row.header_row?
      end

      array
    end

    #
    # Returns the table as a complete CSV String. Headers will be listed first,
    # then all of the field rows.
    #
    # This method assumes you want the Table.headers(), unless you explicitly
    # pass <tt>:write_headers => false</tt>.
    #
    def to_csv(write_headers: true, **options)
      array = write_headers ? [headers.to_csv(**options)] : []
      @table.each do |row|
        array.push(row.fields.to_csv(**options)) unless row.header_row?
      end

      array.join("")
    end
    alias_method :to_s, :to_csv

    #
    # Extracts the nested value specified by the sequence of +index+ or +header+ objects by calling dig at each step,
    # returning nil if any intermediate step is nil.
    #
    def dig(index_or_header, *index_or_headers)
      value = self[index_or_header]
      if value.nil?
        nil
      elsif index_or_headers.empty?
        value
      else
        unless value.respond_to?(:dig)
          raise TypeError, "#{value.class} does not have \#dig method"
        end
        value.dig(*index_or_headers)
      end
    end

    # Shows the mode and size of this table in a US-ASCII String.
    def inspect
      "#<#{self.class} mode:#{@mode} row_count:#{to_a.size}>".encode("US-ASCII")
    end
  end
end
