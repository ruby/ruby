# frozen_string_literal: true

require "forwardable"

class CSV
  #
  # A CSV::Table is a two-dimensional data structure for representing CSV
  # documents.  Tables allow you to work with the data by row or column,
  # manipulate the data, and even convert the results back to CSV, if needed.
  #
  # All tables returned by CSV will be constructed from this class, if header
  # row processing is activated.
  #
  class Table
    #
    # Construct a new CSV::Table from +array_of_rows+, which are expected
    # to be CSV::Row objects.  All rows are assumed to have the same headers.
    #
    # The optional +headers+ parameter can be set to Array of headers.
    # If headers aren't set, headers are fetched from CSV::Row objects.
    # Otherwise, headers() method will return headers being set in
    # headers arugument.
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
    # Returns a duplicate table object, in column mode.  This is handy for
    # chaining in a single call without changing the table mode, but be aware
    # that this method can consume a fair amount of memory for bigger data sets.
    #
    # This method returns the duplicate table for chaining.  Don't chain
    # destructive methods (like []=()) this way though, since you are working
    # with a duplicate.
    #
    def by_col
      self.class.new(@table.dup).by_col!
    end

    #
    # Switches the mode of this table to column mode.  All calls to indexing and
    # iteration methods will work with columns until the mode is changed again.
    #
    # This method returns the table and is safe to chain.
    #
    def by_col!
      @mode = :col

      self
    end

    #
    # Returns a duplicate table object, in mixed mode.  This is handy for
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
    # Switches the mode of this table to mixed mode.  All calls to indexing and
    # iteration methods will use the default intelligent indexing system until
    # the mode is changed again.  In mixed mode an index is assumed to be a row
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
    # Switches the mode of this table to row mode.  All calls to indexing and
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
    # other rows).  An empty Array is returned for empty tables.
    #
    def headers
      @headers.dup
    end

    #
    # In the default mixed mode, this method returns rows for index access and
    # columns for header access.  You can force the index association by first
    # calling by_col!() or by_row!().
    #
    # Columns are returned as an Array of values.  Altering that Array has no
    # effect on the table.
    #
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
    # columns for header access.  You can force the index association by first
    # calling by_col!() or by_row!().
    #
    # Rows may be set to an Array of values (which will inherit the table's
    # headers()) or a CSV::Row.
    #
    # Columns may be set to a single value, which is copied to each row of the
    # column, or an Array of values.  Arrays of values are assigned to rows top
    # to bottom in row major order.  Excess values are ignored and if the Array
    # does not have a value for each row the extra rows will receive a +nil+.
    #
    # Assigning to an existing column or row clobbers the data.  Assigning to
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

    #
    # The mixed mode default is to treat a list of indices as row access,
    # returning the rows indicated.  Anything else is considered columnar
    # access.  For columnar access, the return set has an Array for each row
    # with the values indicated by the headers in each Array.  You can force
    # column or row mode using by_col!() or by_row!().
    #
    # You cannot mix column and row access.
    #
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

    #
    # Adds a new row to the bottom end of this table.  You can provide an Array,
    # which will be converted to a CSV::Row (inheriting the table's headers()),
    # or a CSV::Row.
    #
    # This method returns the table for chaining.
    #
    def <<(row_or_array)
      if row_or_array.is_a? Array  # append Array
        @table << Row.new(headers, row_or_array)
      else                         # append Row
        @table << row_or_array
      end

      self # for chaining
    end

    #
    # A shortcut for appending multiple rows.  Equivalent to:
    #
    #   rows.each { |row| self << row }
    #
    # This method returns the table for chaining.
    #
    def push(*rows)
      rows.each { |row| self << row }

      self # for chaining
    end

    #
    # Removes and returns the indicated columns or rows.  In the default mixed
    # mode indices refer to rows and everything else is assumed to be a column
    # headers.  Use by_col!() or by_row!() to force the lookup.
    #
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

    #
    # Removes any column or row for which the block returns +true+.  In the
    # default mixed mode or row mode, iteration is the standard row major
    # walking of rows.  In column mode, iteration will +yield+ two element
    # tuples containing the column name and an Array of values for that column.
    #
    # This method returns the table for chaining.
    #
    # If no block is given, an Enumerator is returned.
    #
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

    #
    # In the default mixed mode or row mode, iteration is the standard row major
    # walking of rows.  In column mode, iteration will +yield+ two element
    # tuples containing the column name and an Array of values for that column.
    #
    # This method returns the table for chaining.
    #
    # If no block is given, an Enumerator is returned.
    #
    def each(&block)
      return enum_for(__method__) { @mode == :col ? headers.size : size } unless block_given?

      if @mode == :col
        headers.each { |header| yield([header, self[header]]) }
      else
        @table.each(&block)
      end

      self # for chaining
    end

    # Returns +true+ if all rows of this table ==() +other+'s rows.
    def ==(other)
      return @table == other.table if other.is_a? CSV::Table
      @table == other
    end

    #
    # Returns the table as an Array of Arrays.  Headers will be the first row,
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
    # Returns the table as a complete CSV String.  Headers will be listed first,
    # then all of the field rows.
    #
    # This method assumes you want the Table.headers(), unless you explicitly
    # pass <tt>:write_headers => false</tt>.
    #
    def to_csv(write_headers: true, **options)
      array = write_headers ? [headers.to_csv(options)] : []
      @table.each do |row|
        array.push(row.fields.to_csv(options)) unless row.header_row?
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
