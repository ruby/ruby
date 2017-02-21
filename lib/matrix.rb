# encoding: utf-8
# frozen_string_literal: false
#
# = matrix.rb
#
# An implementation of Matrix and Vector classes.
#
# See classes Matrix and Vector for documentation.
#
# Current Maintainer:: Marc-André Lafortune
# Original Author:: Keiju ISHITSUKA
# Original Documentation:: Gavin Sinclair (sourced from <i>Ruby in a Nutshell</i> (Matsumoto, O'Reilly))
##

require "e2mmap.rb"

module ExceptionForMatrix # :nodoc:
  extend Exception2MessageMapper
  def_e2message(TypeError, "wrong argument type %s (expected %s)")
  def_e2message(ArgumentError, "Wrong # of arguments(%d for %d)")

  def_exception("ErrDimensionMismatch", "\#{self.name} dimension mismatch")
  def_exception("ErrNotRegular", "Not Regular Matrix")
  def_exception("ErrOperationNotDefined", "Operation(%s) can\\'t be defined: %s op %s")
  def_exception("ErrOperationNotImplemented", "Sorry, Operation(%s) not implemented: %s op %s")
end

#
# The +Matrix+ class represents a mathematical matrix. It provides methods for creating
# matrices, operating on them arithmetically and algebraically,
# and determining their mathematical properties (trace, rank, inverse, determinant).
#
# == Method Catalogue
#
# To create a matrix:
# * Matrix[*rows]
# * Matrix.[](*rows)
# * Matrix.rows(rows, copy = true)
# * Matrix.columns(columns)
# * Matrix.build(row_count, column_count, &block)
# * Matrix.diagonal(*values)
# * Matrix.scalar(n, value)
# * Matrix.identity(n)
# * Matrix.unit(n)
# * Matrix.I(n)
# * Matrix.zero(n)
# * Matrix.row_vector(row)
# * Matrix.column_vector(column)
# * Matrix.empty(row_count, column_count)
# * Matrix.hstack(*matrices)
# * Matrix.vstack(*matrices)
#
# To access Matrix elements/columns/rows/submatrices/properties:
# * #[](i, j)
# * #row_count (row_size)
# * #column_count (column_size)
# * #row(i)
# * #column(j)
# * #collect
# * #map
# * #each
# * #each_with_index
# * #find_index
# * #minor(*param)
# * #first_minor(row, column)
# * #cofactor(row, column)
# * #adjugate
# * #laplace_expansion(row_or_column: num)
# * #cofactor_expansion(row_or_column: num)
#
# Properties of a matrix:
# * #diagonal?
# * #empty?
# * #hermitian?
# * #lower_triangular?
# * #normal?
# * #orthogonal?
# * #permutation?
# * #real?
# * #regular?
# * #singular?
# * #square?
# * #symmetric?
# * #unitary?
# * #upper_triangular?
# * #zero?
#
# Matrix arithmetic:
# * #*(m)
# * #+(m)
# * #-(m)
# * #/(m)
# * #inverse
# * #inv
# * #**
# * #+@
# * #-@
#
# Matrix functions:
# * #determinant
# * #det
# * #hstack(*matrices)
# * #rank
# * #round
# * #trace
# * #tr
# * #transpose
# * #t
# * #vstack(*matrices)
#
# Matrix decompositions:
# * #eigen
# * #eigensystem
# * #lup
# * #lup_decomposition
#
# Complex arithmetic:
# * conj
# * conjugate
# * imag
# * imaginary
# * real
# * rect
# * rectangular
#
# Conversion to other data types:
# * #coerce(other)
# * #row_vectors
# * #column_vectors
# * #to_a
#
# String representations:
# * #to_s
# * #inspect
#
class Matrix
  include Enumerable
  include ExceptionForMatrix
  autoload :EigenvalueDecomposition, "matrix/eigenvalue_decomposition"
  autoload :LUPDecomposition, "matrix/lup_decomposition"

  # instance creations
  private_class_method :new
  attr_reader :rows
  protected :rows

  #
  # Creates a matrix where each argument is a row.
  #   Matrix[ [25, 93], [-1, 66] ]
  #      =>  25 93
  #          -1 66
  #
  def Matrix.[](*rows)
    rows(rows, false)
  end

  #
  # Creates a matrix where +rows+ is an array of arrays, each of which is a row
  # of the matrix.  If the optional argument +copy+ is false, use the given
  # arrays as the internal structure of the matrix without copying.
  #   Matrix.rows([[25, 93], [-1, 66]])
  #      =>  25 93
  #          -1 66
  #
  def Matrix.rows(rows, copy = true)
    rows = convert_to_array(rows, copy)
    rows.map! do |row|
      convert_to_array(row, copy)
    end
    size = (rows[0] || []).size
    rows.each do |row|
      raise ErrDimensionMismatch, "row size differs (#{row.size} should be #{size})" unless row.size == size
    end
    new rows, size
  end

  #
  # Creates a matrix using +columns+ as an array of column vectors.
  #   Matrix.columns([[25, 93], [-1, 66]])
  #      =>  25 -1
  #          93 66
  #
  def Matrix.columns(columns)
    rows(columns, false).transpose
  end

  #
  # Creates a matrix of size +row_count+ x +column_count+.
  # It fills the values by calling the given block,
  # passing the current row and column.
  # Returns an enumerator if no block is given.
  #
  #   m = Matrix.build(2, 4) {|row, col| col - row }
  #     => Matrix[[0, 1, 2, 3], [-1, 0, 1, 2]]
  #   m = Matrix.build(3) { rand }
  #     => a 3x3 matrix with random elements
  #
  def Matrix.build(row_count, column_count = row_count)
    row_count = CoercionHelper.coerce_to_int(row_count)
    column_count = CoercionHelper.coerce_to_int(column_count)
    raise ArgumentError if row_count < 0 || column_count < 0
    return to_enum :build, row_count, column_count unless block_given?
    rows = Array.new(row_count) do |i|
      Array.new(column_count) do |j|
        yield i, j
      end
    end
    new rows, column_count
  end

  #
  # Creates a matrix where the diagonal elements are composed of +values+.
  #   Matrix.diagonal(9, 5, -3)
  #     =>  9  0  0
  #         0  5  0
  #         0  0 -3
  #
  def Matrix.diagonal(*values)
    size = values.size
    return Matrix.empty if size == 0
    rows = Array.new(size) {|j|
      row = Array.new(size, 0)
      row[j] = values[j]
      row
    }
    new rows
  end

  #
  # Creates an +n+ by +n+ diagonal matrix where each diagonal element is
  # +value+.
  #   Matrix.scalar(2, 5)
  #     => 5 0
  #        0 5
  #
  def Matrix.scalar(n, value)
    diagonal(*Array.new(n, value))
  end

  #
  # Creates an +n+ by +n+ identity matrix.
  #   Matrix.identity(2)
  #     => 1 0
  #        0 1
  #
  def Matrix.identity(n)
    scalar(n, 1)
  end
  class << Matrix
    alias unit identity
    alias I identity
  end

  #
  # Creates a zero matrix.
  #   Matrix.zero(2)
  #     => 0 0
  #        0 0
  #
  def Matrix.zero(row_count, column_count = row_count)
    rows = Array.new(row_count){Array.new(column_count, 0)}
    new rows, column_count
  end

  #
  # Creates a single-row matrix where the values of that row are as given in
  # +row+.
  #   Matrix.row_vector([4,5,6])
  #     => 4 5 6
  #
  def Matrix.row_vector(row)
    row = convert_to_array(row)
    new [row]
  end

  #
  # Creates a single-column matrix where the values of that column are as given
  # in +column+.
  #   Matrix.column_vector([4,5,6])
  #     => 4
  #        5
  #        6
  #
  def Matrix.column_vector(column)
    column = convert_to_array(column)
    new [column].transpose, 1
  end

  #
  # Creates a empty matrix of +row_count+ x +column_count+.
  # At least one of +row_count+ or +column_count+ must be 0.
  #
  #   m = Matrix.empty(2, 0)
  #   m == Matrix[ [], [] ]
  #     => true
  #   n = Matrix.empty(0, 3)
  #   n == Matrix.columns([ [], [], [] ])
  #     => true
  #   m * n
  #     => Matrix[[0, 0, 0], [0, 0, 0]]
  #
  def Matrix.empty(row_count = 0, column_count = 0)
    raise ArgumentError, "One size must be 0" if column_count != 0 && row_count != 0
    raise ArgumentError, "Negative size" if column_count < 0 || row_count < 0

    new([[]]*row_count, column_count)
  end

  #
  # Create a matrix by stacking matrices vertically
  #
  #   x = Matrix[[1, 2], [3, 4]]
  #   y = Matrix[[5, 6], [7, 8]]
  #   Matrix.vstack(x, y) # => Matrix[[1, 2], [3, 4], [5, 6], [7, 8]]
  #
  def Matrix.vstack(x, *matrices)
    raise TypeError, "Expected a Matrix, got a #{x.class}" unless x.is_a?(Matrix)
    result = x.send(:rows).map(&:dup)
    matrices.each do |m|
      raise TypeError, "Expected a Matrix, got a #{m.class}" unless m.is_a?(Matrix)
      if m.column_count != x.column_count
        raise ErrDimensionMismatch, "The given matrices must have #{x.column_count} columns, but one has #{m.column_count}"
      end
      result.concat(m.send(:rows))
    end
    new result, x.column_count
  end


  #
  # Create a matrix by stacking matrices horizontally
  #
  #   x = Matrix[[1, 2], [3, 4]]
  #   y = Matrix[[5, 6], [7, 8]]
  #   Matrix.hstack(x, y) # => Matrix[[1, 2, 5, 6], [3, 4, 7, 8]]
  #
  def Matrix.hstack(x, *matrices)
    raise TypeError, "Expected a Matrix, got a #{x.class}" unless x.is_a?(Matrix)
    result = x.send(:rows).map(&:dup)
    total_column_count = x.column_count
    matrices.each do |m|
      raise TypeError, "Expected a Matrix, got a #{m.class}" unless m.is_a?(Matrix)
      if m.row_count != x.row_count
        raise ErrDimensionMismatch, "The given matrices must have #{x.row_count} rows, but one has #{m.row_count}"
      end
      result.each_with_index do |row, i|
        row.concat m.send(:rows)[i]
      end
      total_column_count += m.column_count
    end
    new result, total_column_count
  end

  #
  # Matrix.new is private; use Matrix.rows, columns, [], etc... to create.
  #
  def initialize(rows, column_count = rows[0].size)
    # No checking is done at this point. rows must be an Array of Arrays.
    # column_count must be the size of the first row, if there is one,
    # otherwise it *must* be specified and can be any integer >= 0
    @rows = rows
    @column_count = column_count
  end

  def new_matrix(rows, column_count = rows[0].size) # :nodoc:
    self.class.send(:new, rows, column_count) # bypass privacy of Matrix.new
  end
  private :new_matrix

  #
  # Returns element (+i+,+j+) of the matrix.  That is: row +i+, column +j+.
  #
  def [](i, j)
    @rows.fetch(i){return nil}[j]
  end
  alias element []
  alias component []

  def []=(i, j, v)
    @rows[i][j] = v
  end
  alias set_element []=
  alias set_component []=
  private :[]=, :set_element, :set_component

  #
  # Returns the number of rows.
  #
  def row_count
    @rows.size
  end

  alias_method :row_size, :row_count
  #
  # Returns the number of columns.
  #
  attr_reader :column_count
  alias_method :column_size, :column_count

  #
  # Returns row vector number +i+ of the matrix as a Vector (starting at 0 like
  # an array).  When a block is given, the elements of that vector are iterated.
  #
  def row(i, &block) # :yield: e
    if block_given?
      @rows.fetch(i){return self}.each(&block)
      self
    else
      Vector.elements(@rows.fetch(i){return nil})
    end
  end

  #
  # Returns column vector number +j+ of the matrix as a Vector (starting at 0
  # like an array).  When a block is given, the elements of that vector are
  # iterated.
  #
  def column(j) # :yield: e
    if block_given?
      return self if j >= column_count || j < -column_count
      row_count.times do |i|
        yield @rows[i][j]
      end
      self
    else
      return nil if j >= column_count || j < -column_count
      col = Array.new(row_count) {|i|
        @rows[i][j]
      }
      Vector.elements(col, false)
    end
  end

  #
  # Returns a matrix that is the result of iteration of the given block over all
  # elements of the matrix.
  #   Matrix[ [1,2], [3,4] ].collect { |e| e**2 }
  #     => 1  4
  #        9 16
  #
  def collect(&block) # :yield: e
    return to_enum(:collect) unless block_given?
    rows = @rows.collect{|row| row.collect(&block)}
    new_matrix rows, column_count
  end
  alias map collect

  #
  # Yields all elements of the matrix, starting with those of the first row,
  # or returns an Enumerator if no block given.
  # Elements can be restricted by passing an argument:
  # * :all (default): yields all elements
  # * :diagonal: yields only elements on the diagonal
  # * :off_diagonal: yields all elements except on the diagonal
  # * :lower: yields only elements on or below the diagonal
  # * :strict_lower: yields only elements below the diagonal
  # * :strict_upper: yields only elements above the diagonal
  # * :upper: yields only elements on or above the diagonal
  #
  #   Matrix[ [1,2], [3,4] ].each { |e| puts e }
  #     # => prints the numbers 1 to 4
  #   Matrix[ [1,2], [3,4] ].each(:strict_lower).to_a # => [3]
  #
  def each(which = :all) # :yield: e
    return to_enum :each, which unless block_given?
    last = column_count - 1
    case which
    when :all
      block = Proc.new
      @rows.each do |row|
        row.each(&block)
      end
    when :diagonal
      @rows.each_with_index do |row, row_index|
        yield row.fetch(row_index){return self}
      end
    when :off_diagonal
      @rows.each_with_index do |row, row_index|
        column_count.times do |col_index|
          yield row[col_index] unless row_index == col_index
        end
      end
    when :lower
      @rows.each_with_index do |row, row_index|
        0.upto([row_index, last].min) do |col_index|
          yield row[col_index]
        end
      end
    when :strict_lower
      @rows.each_with_index do |row, row_index|
        [row_index, column_count].min.times do |col_index|
          yield row[col_index]
        end
      end
    when :strict_upper
      @rows.each_with_index do |row, row_index|
        (row_index+1).upto(last) do |col_index|
          yield row[col_index]
        end
      end
    when :upper
      @rows.each_with_index do |row, row_index|
        row_index.upto(last) do |col_index|
          yield row[col_index]
        end
      end
    else
      raise ArgumentError, "expected #{which.inspect} to be one of :all, :diagonal, :off_diagonal, :lower, :strict_lower, :strict_upper or :upper"
    end
    self
  end

  #
  # Same as #each, but the row index and column index in addition to the element
  #
  #   Matrix[ [1,2], [3,4] ].each_with_index do |e, row, col|
  #     puts "#{e} at #{row}, #{col}"
  #   end
  #     # => Prints:
  #     #    1 at 0, 0
  #     #    2 at 0, 1
  #     #    3 at 1, 0
  #     #    4 at 1, 1
  #
  def each_with_index(which = :all) # :yield: e, row, column
    return to_enum :each_with_index, which unless block_given?
    last = column_count - 1
    case which
    when :all
      @rows.each_with_index do |row, row_index|
        row.each_with_index do |e, col_index|
          yield e, row_index, col_index
        end
      end
    when :diagonal
      @rows.each_with_index do |row, row_index|
        yield row.fetch(row_index){return self}, row_index, row_index
      end
    when :off_diagonal
      @rows.each_with_index do |row, row_index|
        column_count.times do |col_index|
          yield row[col_index], row_index, col_index unless row_index == col_index
        end
      end
    when :lower
      @rows.each_with_index do |row, row_index|
        0.upto([row_index, last].min) do |col_index|
          yield row[col_index], row_index, col_index
        end
      end
    when :strict_lower
      @rows.each_with_index do |row, row_index|
        [row_index, column_count].min.times do |col_index|
          yield row[col_index], row_index, col_index
        end
      end
    when :strict_upper
      @rows.each_with_index do |row, row_index|
        (row_index+1).upto(last) do |col_index|
          yield row[col_index], row_index, col_index
        end
      end
    when :upper
      @rows.each_with_index do |row, row_index|
        row_index.upto(last) do |col_index|
          yield row[col_index], row_index, col_index
        end
      end
    else
      raise ArgumentError, "expected #{which.inspect} to be one of :all, :diagonal, :off_diagonal, :lower, :strict_lower, :strict_upper or :upper"
    end
    self
  end

  SELECTORS = {all: true, diagonal: true, off_diagonal: true, lower: true, strict_lower: true, strict_upper: true, upper: true}.freeze
  #
  # :call-seq:
  #   index(value, selector = :all) -> [row, column]
  #   index(selector = :all){ block } -> [row, column]
  #   index(selector = :all) -> an_enumerator
  #
  # The index method is specialized to return the index as [row, column]
  # It also accepts an optional +selector+ argument, see #each for details.
  #
  #   Matrix[ [1,2], [3,4] ].index(&:even?) # => [0, 1]
  #   Matrix[ [1,1], [1,1] ].index(1, :strict_lower) # => [1, 0]
  #
  def index(*args)
    raise ArgumentError, "wrong number of arguments(#{args.size} for 0-2)" if args.size > 2
    which = (args.size == 2 || SELECTORS.include?(args.last)) ? args.pop : :all
    return to_enum :find_index, which, *args unless block_given? || args.size == 1
    if args.size == 1
      value = args.first
      each_with_index(which) do |e, row_index, col_index|
        return row_index, col_index if e == value
      end
    else
      each_with_index(which) do |e, row_index, col_index|
        return row_index, col_index if yield e
      end
    end
    nil
  end
  alias_method :find_index, :index

  #
  # Returns a section of the matrix.  The parameters are either:
  # *  start_row, nrows, start_col, ncols; OR
  # *  row_range, col_range
  #
  #   Matrix.diagonal(9, 5, -3).minor(0..1, 0..2)
  #     => 9 0 0
  #        0 5 0
  #
  # Like Array#[], negative indices count backward from the end of the
  # row or column (-1 is the last element). Returns nil if the starting
  # row or column is greater than row_count or column_count respectively.
  #
  def minor(*param)
    case param.size
    when 2
      row_range, col_range = param
      from_row = row_range.first
      from_row += row_count if from_row < 0
      to_row = row_range.end
      to_row += row_count if to_row < 0
      to_row += 1 unless row_range.exclude_end?
      size_row = to_row - from_row

      from_col = col_range.first
      from_col += column_count if from_col < 0
      to_col = col_range.end
      to_col += column_count if to_col < 0
      to_col += 1 unless col_range.exclude_end?
      size_col = to_col - from_col
    when 4
      from_row, size_row, from_col, size_col = param
      return nil if size_row < 0 || size_col < 0
      from_row += row_count if from_row < 0
      from_col += column_count if from_col < 0
    else
      raise ArgumentError, param.inspect
    end

    return nil if from_row > row_count || from_col > column_count || from_row < 0 || from_col < 0
    rows = @rows[from_row, size_row].collect{|row|
      row[from_col, size_col]
    }
    new_matrix rows, [column_count - from_col, size_col].min
  end

  #
  # Returns the submatrix obtained by deleting the specified row and column.
  #
  #   Matrix.diagonal(9, 5, -3, 4).first_minor(1, 2)
  #     => 9 0 0
  #        0 0 0
  #        0 0 4
  #
  def first_minor(row, column)
    raise RuntimeError, "first_minor of empty matrix is not defined" if empty?

    unless 0 <= row && row < row_count
      raise ArgumentError, "invalid row (#{row.inspect} for 0..#{row_count - 1})"
    end

    unless 0 <= column && column < column_count
      raise ArgumentError, "invalid column (#{column.inspect} for 0..#{column_count - 1})"
    end

    arrays = to_a
    arrays.delete_at(row)
    arrays.each do |array|
      array.delete_at(column)
    end

    new_matrix arrays, column_count - 1
  end

  #
  # Returns the (row, column) cofactor which is obtained by multiplying
  # the first minor by (-1)**(row + column).
  #
  #   Matrix.diagonal(9, 5, -3, 4).cofactor(1, 1)
  #     => -108
  #
  def cofactor(row, column)
    raise RuntimeError, "cofactor of empty matrix is not defined" if empty?
    Matrix.Raise ErrDimensionMismatch unless square?

    det_of_minor = first_minor(row, column).determinant
    det_of_minor * (-1) ** (row + column)
  end

  #
  # Returns the adjugate of the matrix.
  #
  #   Matrix[ [7,6],[3,9] ].adjugate
  #     => 9 -6
  #        -3 7
  #
  def adjugate
    Matrix.Raise ErrDimensionMismatch unless square?
    Matrix.build(row_count, column_count) do |row, column|
      cofactor(column, row)
    end
  end

  #
  # Returns the Laplace expansion along given row or column.
  #
  #    Matrix[[7,6], [3,9]].laplace_expansion(column: 1)
  #     => 45
  #
  #    Matrix[[Vector[1, 0], Vector[0, 1]], [2, 3]].laplace_expansion(row: 0)
  #     => Vector[3, -2]
  #
  #
  def laplace_expansion(row: nil, column: nil)
    num = row || column

    if !num || (row && column)
      raise ArgumentError, "exactly one the row or column arguments must be specified"
    end

    Matrix.Raise ErrDimensionMismatch unless square?
    raise RuntimeError, "laplace_expansion of empty matrix is not defined" if empty?

    unless 0 <= num && num < row_count
      raise ArgumentError, "invalid num (#{num.inspect} for 0..#{row_count - 1})"
    end

    send(row ? :row : :column, num).map.with_index { |e, k|
      e * cofactor(*(row ? [num, k] : [k,num]))
    }.inject(:+)
  end
  alias_method :cofactor_expansion, :laplace_expansion


  #--
  # TESTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns +true+ if this is a diagonal matrix.
  # Raises an error if matrix is not square.
  #
  def diagonal?
    Matrix.Raise ErrDimensionMismatch unless square?
    each(:off_diagonal).all?(&:zero?)
  end

  #
  # Returns +true+ if this is an empty matrix, i.e. if the number of rows
  # or the number of columns is 0.
  #
  def empty?
    column_count == 0 || row_count == 0
  end

  #
  # Returns +true+ if this is an hermitian matrix.
  # Raises an error if matrix is not square.
  #
  def hermitian?
    Matrix.Raise ErrDimensionMismatch unless square?
    each_with_index(:upper).all? do |e, row, col|
      e == rows[col][row].conj
    end
  end

  #
  # Returns +true+ if this is a lower triangular matrix.
  #
  def lower_triangular?
    each(:strict_upper).all?(&:zero?)
  end

  #
  # Returns +true+ if this is a normal matrix.
  # Raises an error if matrix is not square.
  #
  def normal?
    Matrix.Raise ErrDimensionMismatch unless square?
    rows.each_with_index do |row_i, i|
      rows.each_with_index do |row_j, j|
        s = 0
        rows.each_with_index do |row_k, k|
          s += row_i[k] * row_j[k].conj - row_k[i].conj * row_k[j]
        end
        return false unless s == 0
      end
    end
    true
  end

  #
  # Returns +true+ if this is an orthogonal matrix
  # Raises an error if matrix is not square.
  #
  def orthogonal?
    Matrix.Raise ErrDimensionMismatch unless square?
    rows.each_with_index do |row, i|
      column_count.times do |j|
        s = 0
        row_count.times do |k|
          s += row[k] * rows[k][j]
        end
        return false unless s == (i == j ? 1 : 0)
      end
    end
    true
  end

  #
  # Returns +true+ if this is a permutation matrix
  # Raises an error if matrix is not square.
  #
  def permutation?
    Matrix.Raise ErrDimensionMismatch unless square?
    cols = Array.new(column_count)
    rows.each_with_index do |row, i|
      found = false
      row.each_with_index do |e, j|
        if e == 1
          return false if found || cols[j]
          found = cols[j] = true
        elsif e != 0
          return false
        end
      end
      return false unless found
    end
    true
  end

  #
  # Returns +true+ if all entries of the matrix are real.
  #
  def real?
    all?(&:real?)
  end

  #
  # Returns +true+ if this is a regular (i.e. non-singular) matrix.
  #
  def regular?
    not singular?
  end

  #
  # Returns +true+ if this is a singular matrix.
  #
  def singular?
    determinant == 0
  end

  #
  # Returns +true+ if this is a square matrix.
  #
  def square?
    column_count == row_count
  end

  #
  # Returns +true+ if this is a symmetric matrix.
  # Raises an error if matrix is not square.
  #
  def symmetric?
    Matrix.Raise ErrDimensionMismatch unless square?
    each_with_index(:strict_upper) do |e, row, col|
      return false if e != rows[col][row]
    end
    true
  end

  #
  # Returns +true+ if this is a unitary matrix
  # Raises an error if matrix is not square.
  #
  def unitary?
    Matrix.Raise ErrDimensionMismatch unless square?
    rows.each_with_index do |row, i|
      column_count.times do |j|
        s = 0
        row_count.times do |k|
          s += row[k].conj * rows[k][j]
        end
        return false unless s == (i == j ? 1 : 0)
      end
    end
    true
  end

  #
  # Returns +true+ if this is an upper triangular matrix.
  #
  def upper_triangular?
    each(:strict_lower).all?(&:zero?)
  end

  #
  # Returns +true+ if this is a matrix with only zero elements
  #
  def zero?
    all?(&:zero?)
  end

  #--
  # OBJECT METHODS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns +true+ if and only if the two matrices contain equal elements.
  #
  def ==(other)
    return false unless Matrix === other &&
                        column_count == other.column_count # necessary for empty matrices
    rows == other.rows
  end

  def eql?(other)
    return false unless Matrix === other &&
                        column_count == other.column_count # necessary for empty matrices
    rows.eql? other.rows
  end

  #
  # Returns a clone of the matrix, so that the contents of each do not reference
  # identical objects.
  # There should be no good reason to do this since Matrices are immutable.
  #
  def clone
    new_matrix @rows.map(&:dup), column_count
  end

  #
  # Returns a hash-code for the matrix.
  #
  def hash
    @rows.hash
  end

  #--
  # ARITHMETIC -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Matrix multiplication.
  #   Matrix[[2,4], [6,8]] * Matrix.identity(2)
  #     => 2 4
  #        6 8
  #
  def *(m) # m is matrix or vector or number
    case(m)
    when Numeric
      rows = @rows.collect {|row|
        row.collect {|e| e * m }
      }
      return new_matrix rows, column_count
    when Vector
      m = self.class.column_vector(m)
      r = self * m
      return r.column(0)
    when Matrix
      Matrix.Raise ErrDimensionMismatch if column_count != m.row_count

      rows = Array.new(row_count) {|i|
        Array.new(m.column_count) {|j|
          (0 ... column_count).inject(0) do |vij, k|
            vij + self[i, k] * m[k, j]
          end
        }
      }
      return new_matrix rows, m.column_count
    else
      return apply_through_coercion(m, __method__)
    end
  end

  #
  # Matrix addition.
  #   Matrix.scalar(2,5) + Matrix[[1,0], [-4,7]]
  #     =>  6  0
  #        -4 12
  #
  def +(m)
    case m
    when Numeric
      Matrix.Raise ErrOperationNotDefined, "+", self.class, m.class
    when Vector
      m = self.class.column_vector(m)
    when Matrix
    else
      return apply_through_coercion(m, __method__)
    end

    Matrix.Raise ErrDimensionMismatch unless row_count == m.row_count && column_count == m.column_count

    rows = Array.new(row_count) {|i|
      Array.new(column_count) {|j|
        self[i, j] + m[i, j]
      }
    }
    new_matrix rows, column_count
  end

  #
  # Matrix subtraction.
  #   Matrix[[1,5], [4,2]] - Matrix[[9,3], [-4,1]]
  #     => -8  2
  #         8  1
  #
  def -(m)
    case m
    when Numeric
      Matrix.Raise ErrOperationNotDefined, "-", self.class, m.class
    when Vector
      m = self.class.column_vector(m)
    when Matrix
    else
      return apply_through_coercion(m, __method__)
    end

    Matrix.Raise ErrDimensionMismatch unless row_count == m.row_count && column_count == m.column_count

    rows = Array.new(row_count) {|i|
      Array.new(column_count) {|j|
        self[i, j] - m[i, j]
      }
    }
    new_matrix rows, column_count
  end

  #
  # Matrix division (multiplication by the inverse).
  #   Matrix[[7,6], [3,9]] / Matrix[[2,9], [3,1]]
  #     => -7  1
  #        -3 -6
  #
  def /(other)
    case other
    when Numeric
      rows = @rows.collect {|row|
        row.collect {|e| e / other }
      }
      return new_matrix rows, column_count
    when Matrix
      return self * other.inverse
    else
      return apply_through_coercion(other, __method__)
    end
  end

  #
  # Returns the inverse of the matrix.
  #   Matrix[[-1, -1], [0, -1]].inverse
  #     => -1  1
  #         0 -1
  #
  def inverse
    Matrix.Raise ErrDimensionMismatch unless square?
    self.class.I(row_count).send(:inverse_from, self)
  end
  alias inv inverse

  def inverse_from(src) # :nodoc:
    last = row_count - 1
    a = src.to_a

    0.upto(last) do |k|
      i = k
      akk = a[k][k].abs
      (k+1).upto(last) do |j|
        v = a[j][k].abs
        if v > akk
          i = j
          akk = v
        end
      end
      Matrix.Raise ErrNotRegular if akk == 0
      if i != k
        a[i], a[k] = a[k], a[i]
        @rows[i], @rows[k] = @rows[k], @rows[i]
      end
      akk = a[k][k]

      0.upto(last) do |ii|
        next if ii == k
        q = a[ii][k].quo(akk)
        a[ii][k] = 0

        (k + 1).upto(last) do |j|
          a[ii][j] -= a[k][j] * q
        end
        0.upto(last) do |j|
          @rows[ii][j] -= @rows[k][j] * q
        end
      end

      (k+1).upto(last) do |j|
        a[k][j] = a[k][j].quo(akk)
      end
      0.upto(last) do |j|
        @rows[k][j] = @rows[k][j].quo(akk)
      end
    end
    self
  end
  private :inverse_from

  #
  # Matrix exponentiation.
  # Equivalent to multiplying the matrix by itself N times.
  # Non integer exponents will be handled by diagonalizing the matrix.
  #
  #   Matrix[[7,6], [3,9]] ** 2
  #     => 67 96
  #        48 99
  #
  def **(other)
    case other
    when Integer
      x = self
      if other <= 0
        x = self.inverse
        return self.class.identity(self.column_count) if other == 0
        other = -other
      end
      z = nil
      loop do
        z = z ? z * x : x if other[0] == 1
        return z if (other >>= 1).zero?
        x *= x
      end
    when Numeric
      v, d, v_inv = eigensystem
      v * self.class.diagonal(*d.each(:diagonal).map{|e| e ** other}) * v_inv
    else
      Matrix.Raise ErrOperationNotDefined, "**", self.class, other.class
    end
  end

  def +@
    self
  end

  def -@
    collect {|e| -e }
  end

  #--
  # MATRIX FUNCTIONS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns the determinant of the matrix.
  #
  # Beware that using Float values can yield erroneous results
  # because of their lack of precision.
  # Consider using exact types like Rational or BigDecimal instead.
  #
  #   Matrix[[7,6], [3,9]].determinant
  #     => 45
  #
  def determinant
    Matrix.Raise ErrDimensionMismatch unless square?
    m = @rows
    case row_count
      # Up to 4x4, give result using Laplacian expansion by minors.
      # This will typically be faster, as well as giving good results
      # in case of Floats
    when 0
      +1
    when 1
      + m[0][0]
    when 2
      + m[0][0] * m[1][1] - m[0][1] * m[1][0]
    when 3
      m0, m1, m2 = m
      + m0[0] * m1[1] * m2[2] - m0[0] * m1[2] * m2[1] \
      - m0[1] * m1[0] * m2[2] + m0[1] * m1[2] * m2[0] \
      + m0[2] * m1[0] * m2[1] - m0[2] * m1[1] * m2[0]
    when 4
      m0, m1, m2, m3 = m
      + m0[0] * m1[1] * m2[2] * m3[3] - m0[0] * m1[1] * m2[3] * m3[2] \
      - m0[0] * m1[2] * m2[1] * m3[3] + m0[0] * m1[2] * m2[3] * m3[1] \
      + m0[0] * m1[3] * m2[1] * m3[2] - m0[0] * m1[3] * m2[2] * m3[1] \
      - m0[1] * m1[0] * m2[2] * m3[3] + m0[1] * m1[0] * m2[3] * m3[2] \
      + m0[1] * m1[2] * m2[0] * m3[3] - m0[1] * m1[2] * m2[3] * m3[0] \
      - m0[1] * m1[3] * m2[0] * m3[2] + m0[1] * m1[3] * m2[2] * m3[0] \
      + m0[2] * m1[0] * m2[1] * m3[3] - m0[2] * m1[0] * m2[3] * m3[1] \
      - m0[2] * m1[1] * m2[0] * m3[3] + m0[2] * m1[1] * m2[3] * m3[0] \
      + m0[2] * m1[3] * m2[0] * m3[1] - m0[2] * m1[3] * m2[1] * m3[0] \
      - m0[3] * m1[0] * m2[1] * m3[2] + m0[3] * m1[0] * m2[2] * m3[1] \
      + m0[3] * m1[1] * m2[0] * m3[2] - m0[3] * m1[1] * m2[2] * m3[0] \
      - m0[3] * m1[2] * m2[0] * m3[1] + m0[3] * m1[2] * m2[1] * m3[0]
    else
      # For bigger matrices, use an efficient and general algorithm.
      # Currently, we use the Gauss-Bareiss algorithm
      determinant_bareiss
    end
  end
  alias_method :det, :determinant

  #
  # Private. Use Matrix#determinant
  #
  # Returns the determinant of the matrix, using
  # Bareiss' multistep integer-preserving gaussian elimination.
  # It has the same computational cost order O(n^3) as standard Gaussian elimination.
  # Intermediate results are fraction free and of lower complexity.
  # A matrix of Integers will have thus intermediate results that are also Integers,
  # with smaller bignums (if any), while a matrix of Float will usually have
  # intermediate results with better precision.
  #
  def determinant_bareiss
    size = row_count
    last = size - 1
    a = to_a
    no_pivot = Proc.new{ return 0 }
    sign = +1
    pivot = 1
    size.times do |k|
      previous_pivot = pivot
      if (pivot = a[k][k]) == 0
        switch = (k+1 ... size).find(no_pivot) {|row|
          a[row][k] != 0
        }
        a[switch], a[k] = a[k], a[switch]
        pivot = a[k][k]
        sign = -sign
      end
      (k+1).upto(last) do |i|
        ai = a[i]
        (k+1).upto(last) do |j|
          ai[j] =  (pivot * ai[j] - ai[k] * a[k][j]) / previous_pivot
        end
      end
    end
    sign * pivot
  end
  private :determinant_bareiss

  #
  # deprecated; use Matrix#determinant
  #
  def determinant_e
    warn "#{caller(1)[0]}: warning: Matrix#determinant_e is deprecated; use #determinant"
    determinant
  end
  alias det_e determinant_e

  #
  # Returns a new matrix resulting by stacking horizontally
  # the receiver with the given matrices
  #
  #   x = Matrix[[1, 2], [3, 4]]
  #   y = Matrix[[5, 6], [7, 8]]
  #   x.hstack(y) # => Matrix[[1, 2, 5, 6], [3, 4, 7, 8]]
  #
  def hstack(*matrices)
    self.class.hstack(self, *matrices)
  end

  #
  # Returns the rank of the matrix.
  # Beware that using Float values can yield erroneous results
  # because of their lack of precision.
  # Consider using exact types like Rational or BigDecimal instead.
  #
  #   Matrix[[7,6], [3,9]].rank
  #     => 2
  #
  def rank
    # We currently use Bareiss' multistep integer-preserving gaussian elimination
    # (see comments on determinant)
    a = to_a
    last_column = column_count - 1
    last_row = row_count - 1
    pivot_row = 0
    previous_pivot = 1
    0.upto(last_column) do |k|
      switch_row = (pivot_row .. last_row).find {|row|
        a[row][k] != 0
      }
      if switch_row
        a[switch_row], a[pivot_row] = a[pivot_row], a[switch_row] unless pivot_row == switch_row
        pivot = a[pivot_row][k]
        (pivot_row+1).upto(last_row) do |i|
           ai = a[i]
           (k+1).upto(last_column) do |j|
             ai[j] =  (pivot * ai[j] - ai[k] * a[pivot_row][j]) / previous_pivot
           end
         end
        pivot_row += 1
        previous_pivot = pivot
      end
    end
    pivot_row
  end

  #
  # deprecated; use Matrix#rank
  #
  def rank_e
    warn "#{caller(1)[0]}: warning: Matrix#rank_e is deprecated; use #rank"
    rank
  end

  # Returns a matrix with entries rounded to the given precision
  # (see Float#round)
  #
  def round(ndigits=0)
    map{|e| e.round(ndigits)}
  end

  #
  # Returns the trace (sum of diagonal elements) of the matrix.
  #   Matrix[[7,6], [3,9]].trace
  #     => 16
  #
  def trace
    Matrix.Raise ErrDimensionMismatch unless square?
    (0...column_count).inject(0) do |tr, i|
      tr + @rows[i][i]
    end
  end
  alias tr trace

  #
  # Returns the transpose of the matrix.
  #   Matrix[[1,2], [3,4], [5,6]]
  #     => 1 2
  #        3 4
  #        5 6
  #   Matrix[[1,2], [3,4], [5,6]].transpose
  #     => 1 3 5
  #        2 4 6
  #
  def transpose
    return self.class.empty(column_count, 0) if row_count.zero?
    new_matrix @rows.transpose, row_count
  end
  alias t transpose

  #
  # Returns a new matrix resulting by stacking vertically
  # the receiver with the given matrices
  #
  #   x = Matrix[[1, 2], [3, 4]]
  #   y = Matrix[[5, 6], [7, 8]]
  #   x.vstack(y) # => Matrix[[1, 2], [3, 4], [5, 6], [7, 8]]
  #
  def vstack(*matrices)
    self.class.vstack(self, *matrices)
  end

  #--
  # DECOMPOSITIONS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  #++

  #
  # Returns the Eigensystem of the matrix; see +EigenvalueDecomposition+.
  #   m = Matrix[[1, 2], [3, 4]]
  #   v, d, v_inv = m.eigensystem
  #   d.diagonal? # => true
  #   v.inv == v_inv # => true
  #   (v * d * v_inv).round(5) == m # => true
  #
  def eigensystem
    EigenvalueDecomposition.new(self)
  end
  alias eigen eigensystem

  #
  # Returns the LUP decomposition of the matrix; see +LUPDecomposition+.
  #   a = Matrix[[1, 2], [3, 4]]
  #   l, u, p = a.lup
  #   l.lower_triangular? # => true
  #   u.upper_triangular? # => true
  #   p.permutation?      # => true
  #   l * u == p * a      # => true
  #   a.lup.solve([2, 5]) # => Vector[(1/1), (1/2)]
  #
  def lup
    LUPDecomposition.new(self)
  end
  alias lup_decomposition lup

  #--
  # COMPLEX ARITHMETIC -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  #++

  #
  # Returns the conjugate of the matrix.
  #   Matrix[[Complex(1,2), Complex(0,1), 0], [1, 2, 3]]
  #     => 1+2i   i  0
  #           1   2  3
  #   Matrix[[Complex(1,2), Complex(0,1), 0], [1, 2, 3]].conjugate
  #     => 1-2i  -i  0
  #           1   2  3
  #
  def conjugate
    collect(&:conjugate)
  end
  alias conj conjugate

  #
  # Returns the imaginary part of the matrix.
  #   Matrix[[Complex(1,2), Complex(0,1), 0], [1, 2, 3]]
  #     => 1+2i  i  0
  #           1  2  3
  #   Matrix[[Complex(1,2), Complex(0,1), 0], [1, 2, 3]].imaginary
  #     =>   2i  i  0
  #           0  0  0
  #
  def imaginary
    collect(&:imaginary)
  end
  alias imag imaginary

  #
  # Returns the real part of the matrix.
  #   Matrix[[Complex(1,2), Complex(0,1), 0], [1, 2, 3]]
  #     => 1+2i  i  0
  #           1  2  3
  #   Matrix[[Complex(1,2), Complex(0,1), 0], [1, 2, 3]].real
  #     =>    1  0  0
  #           1  2  3
  #
  def real
    collect(&:real)
  end

  #
  # Returns an array containing matrices corresponding to the real and imaginary
  # parts of the matrix
  #
  # m.rect == [m.real, m.imag]  # ==> true for all matrices m
  #
  def rect
    [real, imag]
  end
  alias rectangular rect

  #--
  # CONVERTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # The coerce method provides support for Ruby type coercion.
  # This coercion mechanism is used by Ruby to handle mixed-type
  # numeric operations: it is intended to find a compatible common
  # type between the two operands of the operator.
  # See also Numeric#coerce.
  #
  def coerce(other)
    case other
    when Numeric
      return Scalar.new(other), self
    else
      raise TypeError, "#{self.class} can't be coerced into #{other.class}"
    end
  end

  #
  # Returns an array of the row vectors of the matrix.  See Vector.
  #
  def row_vectors
    Array.new(row_count) {|i|
      row(i)
    }
  end

  #
  # Returns an array of the column vectors of the matrix.  See Vector.
  #
  def column_vectors
    Array.new(column_count) {|i|
      column(i)
    }
  end

  #
  # Returns an array of arrays that describe the rows of the matrix.
  #
  def to_a
    @rows.collect(&:dup)
  end

  def elements_to_f
    warn "#{caller(1)[0]}: warning: Matrix#elements_to_f is deprecated, use map(&:to_f)"
    map(&:to_f)
  end

  def elements_to_i
    warn "#{caller(1)[0]}: warning: Matrix#elements_to_i is deprecated, use map(&:to_i)"
    map(&:to_i)
  end

  def elements_to_r
    warn "#{caller(1)[0]}: warning: Matrix#elements_to_r is deprecated, use map(&:to_r)"
    map(&:to_r)
  end

  #--
  # PRINTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Overrides Object#to_s
  #
  def to_s
    if empty?
      "#{self.class}.empty(#{row_count}, #{column_count})"
    else
      "#{self.class}[" + @rows.collect{|row|
        "[" + row.collect{|e| e.to_s}.join(", ") + "]"
      }.join(", ")+"]"
    end
  end

  #
  # Overrides Object#inspect
  #
  def inspect
    if empty?
      "#{self.class}.empty(#{row_count}, #{column_count})"
    else
      "#{self.class}#{@rows.inspect}"
    end
  end

  # Private helper modules

  module ConversionHelper # :nodoc:
    #
    # Converts the obj to an Array. If copy is set to true
    # a copy of obj will be made if necessary.
    #
    def convert_to_array(obj, copy = false) # :nodoc:
      case obj
      when Array
        copy ? obj.dup : obj
      when Vector
        obj.to_a
      else
        begin
          converted = obj.to_ary
        rescue Exception => e
          raise TypeError, "can't convert #{obj.class} into an Array (#{e.message})"
        end
        raise TypeError, "#{obj.class}#to_ary should return an Array" unless converted.is_a? Array
        converted
      end
    end
    private :convert_to_array
  end

  extend ConversionHelper

  module CoercionHelper # :nodoc:
    #
    # Applies the operator +oper+ with argument +obj+
    # through coercion of +obj+
    #
    def apply_through_coercion(obj, oper)
      coercion = obj.coerce(self)
      raise TypeError unless coercion.is_a?(Array) && coercion.length == 2
      coercion[0].public_send(oper, coercion[1])
    rescue
      raise TypeError, "#{obj.inspect} can't be coerced into #{self.class}"
    end
    private :apply_through_coercion

    #
    # Helper method to coerce a value into a specific class.
    # Raises a TypeError if the coercion fails or the returned value
    # is not of the right class.
    # (from Rubinius)
    #
    def self.coerce_to(obj, cls, meth) # :nodoc:
      return obj if obj.kind_of?(cls)

      begin
        ret = obj.__send__(meth)
      rescue Exception => e
        raise TypeError, "Coercion error: #{obj.inspect}.#{meth} => #{cls} failed:\n" \
                         "(#{e.message})"
      end
      raise TypeError, "Coercion error: obj.#{meth} did NOT return a #{cls} (was #{ret.class})" unless ret.kind_of? cls
      ret
    end

    def self.coerce_to_int(obj)
      coerce_to(obj, Integer, :to_int)
    end
  end

  include CoercionHelper

  # Private CLASS

  class Scalar < Numeric # :nodoc:
    include ExceptionForMatrix
    include CoercionHelper

    def initialize(value)
      @value = value
    end

    # ARITHMETIC
    def +(other)
      case other
      when Numeric
        Scalar.new(@value + other)
      when Vector, Matrix
        Scalar.Raise ErrOperationNotDefined, "+", @value.class, other.class
      else
        apply_through_coercion(other, __method__)
      end
    end

    def -(other)
      case other
      when Numeric
        Scalar.new(@value - other)
      when Vector, Matrix
        Scalar.Raise ErrOperationNotDefined, "-", @value.class, other.class
      else
        apply_through_coercion(other, __method__)
      end
    end

    def *(other)
      case other
      when Numeric
        Scalar.new(@value * other)
      when Vector, Matrix
        other.collect{|e| @value * e}
      else
        apply_through_coercion(other, __method__)
      end
    end

    def /(other)
      case other
      when Numeric
        Scalar.new(@value / other)
      when Vector
        Scalar.Raise ErrOperationNotDefined, "/", @value.class, other.class
      when Matrix
        self * other.inverse
      else
        apply_through_coercion(other, __method__)
      end
    end

    def **(other)
      case other
      when Numeric
        Scalar.new(@value ** other)
      when Vector
        Scalar.Raise ErrOperationNotDefined, "**", @value.class, other.class
      when Matrix
        #other.powered_by(self)
        Scalar.Raise ErrOperationNotImplemented, "**", @value.class, other.class
      else
        apply_through_coercion(other, __method__)
      end
    end
  end

end


#
# The +Vector+ class represents a mathematical vector, which is useful in its own right, and
# also constitutes a row or column of a Matrix.
#
# == Method Catalogue
#
# To create a Vector:
# * Vector.[](*array)
# * Vector.elements(array, copy = true)
# * Vector.basis(size: n, index: k)
#
# To access elements:
# * #[](i)
#
# To enumerate the elements:
# * #each2(v)
# * #collect2(v)
#
# Properties of vectors:
# * #angle_with(v)
# * Vector.independent?(*vs)
# * #independent?(*vs)
#
# Vector arithmetic:
# * #*(x) "is matrix or number"
# * #+(v)
# * #-(v)
# * #/(v)
# * #+@
# * #-@
#
# Vector functions:
# * #inner_product(v), dot(v)
# * #cross_product(v), cross(v)
# * #collect
# * #magnitude
# * #map
# * #map2(v)
# * #norm
# * #normalize
# * #r
# * #round
# * #size
#
# Conversion to other data types:
# * #covector
# * #to_a
# * #coerce(other)
#
# String representations:
# * #to_s
# * #inspect
#
class Vector
  include ExceptionForMatrix
  include Enumerable
  include Matrix::CoercionHelper
  extend Matrix::ConversionHelper
  #INSTANCE CREATION

  private_class_method :new
  attr_reader :elements
  protected :elements

  #
  # Creates a Vector from a list of elements.
  #   Vector[7, 4, ...]
  #
  def Vector.[](*array)
    new convert_to_array(array, false)
  end

  #
  # Creates a vector from an Array.  The optional second argument specifies
  # whether the array itself or a copy is used internally.
  #
  def Vector.elements(array, copy = true)
    new convert_to_array(array, copy)
  end

  #
  # Returns a standard basis +n+-vector, where k is the index.
  #
  #    Vector.basis(size:, index:) # => Vector[0, 1, 0]
  #
  def Vector.basis(size:, index:)
    raise ArgumentError, "invalid size (#{size} for 1..)" if size < 1
    raise ArgumentError, "invalid index (#{index} for 0...#{size})" unless 0 <= index && index < size
    array = Array.new(size, 0)
    array[index] = 1
    new convert_to_array(array, false)
  end

  #
  # Vector.new is private; use Vector[] or Vector.elements to create.
  #
  def initialize(array)
    # No checking is done at this point.
    @elements = array
  end

  # ACCESSING

  #
  # Returns element number +i+ (starting at zero) of the vector.
  #
  def [](i)
    @elements[i]
  end
  alias element []
  alias component []

  def []=(i, v)
    @elements[i]= v
  end
  alias set_element []=
  alias set_component []=
  private :[]=, :set_element, :set_component

  # Returns a vector with entries rounded to the given precision
  # (see Float#round)
  #
  def round(ndigits=0)
    map{|e| e.round(ndigits)}
  end

  #
  # Returns the number of elements in the vector.
  #
  def size
    @elements.size
  end

  #--
  # ENUMERATIONS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Iterate over the elements of this vector
  #
  def each(&block)
    return to_enum(:each) unless block_given?
    @elements.each(&block)
    self
  end

  #
  # Iterate over the elements of this vector and +v+ in conjunction.
  #
  def each2(v) # :yield: e1, e2
    raise TypeError, "Integer is not like Vector" if v.kind_of?(Integer)
    Vector.Raise ErrDimensionMismatch if size != v.size
    return to_enum(:each2, v) unless block_given?
    size.times do |i|
      yield @elements[i], v[i]
    end
    self
  end

  #
  # Collects (as in Enumerable#collect) over the elements of this vector and +v+
  # in conjunction.
  #
  def collect2(v) # :yield: e1, e2
    raise TypeError, "Integer is not like Vector" if v.kind_of?(Integer)
    Vector.Raise ErrDimensionMismatch if size != v.size
    return to_enum(:collect2, v) unless block_given?
    Array.new(size) do |i|
      yield @elements[i], v[i]
    end
  end

  #--
  # PROPERTIES -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns +true+ iff all of vectors are linearly independent.
  #
  #   Vector.independent?(Vector[1,0], Vector[0,1])
  #     => true
  #
  #   Vector.independent?(Vector[1,2], Vector[2,4])
  #     => false
  #
  def Vector.independent?(*vs)
    vs.each do |v|
      raise TypeError, "expected Vector, got #{v.class}" unless v.is_a?(Vector)
      Vector.Raise ErrDimensionMismatch unless v.size == vs.first.size
    end
    return false if vs.count > vs.first.size
    Matrix[*vs].rank.eql?(vs.count)
  end

  #
  # Returns +true+ iff all of vectors are linearly independent.
  #
  #   Vector[1,0].independent?(Vector[0,1])
  #     => true
  #
  #   Vector[1,2].independent?(Vector[2,4])
  #     => false
  #
  def independent?(*vs)
    self.class.independent?(self, *vs)
  end

  #--
  # COMPARING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns +true+ iff the two vectors have the same elements in the same order.
  #
  def ==(other)
    return false unless Vector === other
    @elements == other.elements
  end

  def eql?(other)
    return false unless Vector === other
    @elements.eql? other.elements
  end

  #
  # Returns a copy of the vector.
  #
  def clone
    self.class.elements(@elements)
  end

  #
  # Returns a hash-code for the vector.
  #
  def hash
    @elements.hash
  end

  #--
  # ARITHMETIC -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Multiplies the vector by +x+, where +x+ is a number or a matrix.
  #
  def *(x)
    case x
    when Numeric
      els = @elements.collect{|e| e * x}
      self.class.elements(els, false)
    when Matrix
      Matrix.column_vector(self) * x
    when Vector
      Vector.Raise ErrOperationNotDefined, "*", self.class, x.class
    else
      apply_through_coercion(x, __method__)
    end
  end

  #
  # Vector addition.
  #
  def +(v)
    case v
    when Vector
      Vector.Raise ErrDimensionMismatch if size != v.size
      els = collect2(v) {|v1, v2|
        v1 + v2
      }
      self.class.elements(els, false)
    when Matrix
      Matrix.column_vector(self) + v
    else
      apply_through_coercion(v, __method__)
    end
  end

  #
  # Vector subtraction.
  #
  def -(v)
    case v
    when Vector
      Vector.Raise ErrDimensionMismatch if size != v.size
      els = collect2(v) {|v1, v2|
        v1 - v2
      }
      self.class.elements(els, false)
    when Matrix
      Matrix.column_vector(self) - v
    else
      apply_through_coercion(v, __method__)
    end
  end

  #
  # Vector division.
  #
  def /(x)
    case x
    when Numeric
      els = @elements.collect{|e| e / x}
      self.class.elements(els, false)
    when Matrix, Vector
      Vector.Raise ErrOperationNotDefined, "/", self.class, x.class
    else
      apply_through_coercion(x, __method__)
    end
  end

  def +@
    self
  end

  def -@
    collect {|e| -e }
  end

  #--
  # VECTOR FUNCTIONS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns the inner product of this vector with the other.
  #   Vector[4,7].inner_product Vector[10,1]  => 47
  #
  def inner_product(v)
    Vector.Raise ErrDimensionMismatch if size != v.size

    p = 0
    each2(v) {|v1, v2|
      p += v1 * v2.conj
    }
    p
  end
  alias_method :dot, :inner_product

  #
  # Returns the cross product of this vector with the others.
  #   Vector[1, 0, 0].cross_product Vector[0, 1, 0]   => Vector[0, 0, 1]
  #
  # It is generalized to other dimensions to return a vector perpendicular
  # to the arguments.
  #   Vector[1, 2].cross_product # => Vector[-2, 1]
  #   Vector[1, 0, 0, 0].cross_product(
  #      Vector[0, 1, 0, 0],
  #      Vector[0, 0, 1, 0]
  #   )  #=> Vector[0, 0, 0, 1]
  #
  def cross_product(*vs)
    raise ErrOperationNotDefined, "cross product is not defined on vectors of dimension #{size}" unless size >= 2
    raise ArgumentError, "wrong number of arguments (#{vs.size} for #{size - 2})" unless vs.size == size - 2
    vs.each do |v|
      raise TypeError, "expected Vector, got #{v.class}" unless v.is_a? Vector
      Vector.Raise ErrDimensionMismatch unless v.size == size
    end
    case size
    when 2
      Vector[-@elements[1], @elements[0]]
    when 3
      v = vs[0]
      Vector[ v[2]*@elements[1] - v[1]*@elements[2],
        v[0]*@elements[2] - v[2]*@elements[0],
        v[1]*@elements[0] - v[0]*@elements[1] ]
    else
      rows = self, *vs, Array.new(size) {|i| Vector.basis(size: size, index: i) }
      Matrix.rows(rows).laplace_expansion(row: size - 1)
    end
  end
  alias_method :cross, :cross_product

  #
  # Like Array#collect.
  #
  def collect(&block) # :yield: e
    return to_enum(:collect) unless block_given?
    els = @elements.collect(&block)
    self.class.elements(els, false)
  end
  alias map collect

  #
  # Returns the modulus (Pythagorean distance) of the vector.
  #   Vector[5,8,2].r => 9.643650761
  #
  def magnitude
    Math.sqrt(@elements.inject(0) {|v, e| v + e.abs2})
  end
  alias r magnitude
  alias norm magnitude

  #
  # Like Vector#collect2, but returns a Vector instead of an Array.
  #
  def map2(v, &block) # :yield: e1, e2
    return to_enum(:map2, v) unless block_given?
    els = collect2(v, &block)
    self.class.elements(els, false)
  end

  class ZeroVectorError < StandardError
  end
  #
  # Returns a new vector with the same direction but with norm 1.
  #   v = Vector[5,8,2].normalize
  #   # => Vector[0.5184758473652127, 0.8295613557843402, 0.20739033894608505]
  #   v.norm => 1.0
  #
  def normalize
    n = magnitude
    raise ZeroVectorError, "Zero vectors can not be normalized" if n == 0
    self / n
  end

  #
  # Returns an angle with another vector. Result is within the [0...Math::PI].
  #   Vector[1,0].angle_with(Vector[0,1])
  #   # => Math::PI / 2
  #
  def angle_with(v)
    raise TypeError, "Expected a Vector, got a #{v.class}" unless v.is_a?(Vector)
    Vector.Raise ErrDimensionMismatch if size != v.size
    prod = magnitude * v.magnitude
    raise ZeroVectorError, "Can't get angle of zero vector" if prod == 0

    Math.acos( inner_product(v) / prod )
  end

  #--
  # CONVERTING
  #++

  #
  # Creates a single-row matrix from this vector.
  #
  def covector
    Matrix.row_vector(self)
  end

  #
  # Returns the elements of the vector in an array.
  #
  def to_a
    @elements.dup
  end

  def elements_to_f
    warn "#{caller(1)[0]}: warning: Vector#elements_to_f is deprecated"
    map(&:to_f)
  end

  def elements_to_i
    warn "#{caller(1)[0]}: warning: Vector#elements_to_i is deprecated"
    map(&:to_i)
  end

  def elements_to_r
    warn "#{caller(1)[0]}: warning: Vector#elements_to_r is deprecated"
    map(&:to_r)
  end

  #
  # The coerce method provides support for Ruby type coercion.
  # This coercion mechanism is used by Ruby to handle mixed-type
  # numeric operations: it is intended to find a compatible common
  # type between the two operands of the operator.
  # See also Numeric#coerce.
  #
  def coerce(other)
    case other
    when Numeric
      return Matrix::Scalar.new(other), self
    else
      raise TypeError, "#{self.class} can't be coerced into #{other.class}"
    end
  end

  #--
  # PRINTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Overrides Object#to_s
  #
  def to_s
    "Vector[" + @elements.join(", ") + "]"
  end

  #
  # Overrides Object#inspect
  #
  def inspect
    "Vector" + @elements.inspect
  end
end
