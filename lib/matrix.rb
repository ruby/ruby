#--
#   matrix.rb -
#   	$Release Version: 1.0$
#   	$Revision: 1.13 $
#       Original Version from Smalltalk-80 version
#          on July 23, 1985 at 8:37:17 am
#       by Keiju ISHITSUKA
#++
#
# = matrix.rb
#
# An implementation of Matrix and Vector classes.
#
# Author:: Keiju ISHITSUKA
# Documentation:: Gavin Sinclair (sourced from <i>Ruby in a Nutshell</i> (Matsumoto, O'Reilly))
#
# See classes Matrix and Vector for documentation.
#

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
# The +Matrix+ class represents a mathematical matrix, and provides methods for creating
# special-case matrices (zero, identity, diagonal, singular, vector), operating on them
# arithmetically and algebraically, and determining their mathematical properties (trace, rank,
# inverse, determinant).
#
# Note that matrices must be rectangular, otherwise an ErrDimensionMismatch is raised.
#
# Also note that the determinant of integer matrices may be approximated unless you
# also <tt>require 'mathn'</tt>.  This may be fixed in the future.
#
# == Method Catalogue
#
# To create a matrix:
# * <tt> Matrix[*rows]                  </tt>
# * <tt> Matrix.[](*rows)               </tt>
# * <tt> Matrix.rows(rows, copy = true) </tt>
# * <tt> Matrix.columns(columns)        </tt>
# * <tt> Matrix.build(row_size, column_size, &block) </tt>
# * <tt> Matrix.diagonal(*values)       </tt>
# * <tt> Matrix.scalar(n, value)        </tt>
# * <tt> Matrix.identity(n)             </tt>
# * <tt> Matrix.unit(n)                 </tt>
# * <tt> Matrix.I(n)                    </tt>
# * <tt> Matrix.zero(n)                 </tt>
# * <tt> Matrix.row_vector(row)         </tt>
# * <tt> Matrix.column_vector(column)   </tt>
#
# To access Matrix elements/columns/rows/submatrices/properties:
# * <tt>  [](i, j)                      </tt>
# * <tt> #row_size                      </tt>
# * <tt> #column_size                   </tt>
# * <tt> #row(i)                        </tt>
# * <tt> #column(j)                     </tt>
# * <tt> #collect                       </tt>
# * <tt> #map                           </tt>
# * <tt> #each                          </tt>
# * <tt> #each_with_index               </tt>
# * <tt> #minor(*param)                 </tt>
#
# Properties of a matrix:
# * <tt> #empty?                        </tt>
# * <tt> #real?                         </tt>
# * <tt> #regular?                      </tt>
# * <tt> #singular?                     </tt>
# * <tt> #square?                       </tt>
#
# Matrix arithmetic:
# * <tt>  *(m)                          </tt>
# * <tt>  +(m)                          </tt>
# * <tt>  -(m)                          </tt>
# * <tt> #/(m)                          </tt>
# * <tt> #inverse                       </tt>
# * <tt> #inv                           </tt>
# * <tt>  **                            </tt>
#
# Matrix functions:
# * <tt> #determinant                   </tt>
# * <tt> #det                           </tt>
# * <tt> #rank                          </tt>
# * <tt> #trace                         </tt>
# * <tt> #tr                            </tt>
# * <tt> #transpose                     </tt>
# * <tt> #t                             </tt>
#
# Complex arithmetic:
# * <tt> conj                           </tt>
# * <tt> conjugate                      </tt>
# * <tt> imag                           </tt>
# * <tt> imaginary                      </tt>
# * <tt> real                           </tt>
# * <tt> rect                           </tt>
# * <tt> rectangular                    </tt>
#
# Conversion to other data types:
# * <tt> #coerce(other)                 </tt>
# * <tt> #row_vectors                   </tt>
# * <tt> #column_vectors                </tt>
# * <tt> #to_a                          </tt>
#
# String representations:
# * <tt> #to_s                          </tt>
# * <tt> #inspect                       </tt>
#
class Matrix
  @RCS_ID='-$Id: matrix.rb,v 1.13 2001/12/09 14:22:23 keiju Exp keiju $-'

#  extend Exception2MessageMapper
  include Enumerable
  include ExceptionForMatrix

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
    Matrix.rows(rows, false)
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
    rows = Matrix.convert_to_array(rows)
    rows.map! do |row|
      Matrix.convert_to_array(row, copy)
    end
    size = (rows[0] || []).size
    rows.each do |row|
      Matrix.Raise ErrDimensionMismatch, "element size differs (#{row.size} should be #{size})" unless row.size == size
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
    Matrix.rows(columns, false).transpose
  end

  #
  # Creates a matrix of size +row_size+ x +column_size+.
  # It fills the values by calling the given block,
  # passing the current row and column.
  # Returns an enumerator if no block is given.
  #
  #   m = Matrix.build(2, 4) {|row, col| col - row }
  #     => Matrix[[0, 1, 2, 3], [-1, 0, 1, 2]]
  #   m = Matrix.build(3) { rand }
  #     => a 3x3 matrix with random elements
  #
  def Matrix.build(row_size, column_size = row_size)
    row_size = CoercionHelper.coerce_to_int(row_size)
    column_size = CoercionHelper.coerce_to_int(column_size)
    raise ArgumentError if row_size < 0 || column_size < 0
    return to_enum :build, row_size, column_size unless block_given?
    rows = row_size.times.map do |i|
      column_size.times.map do |j|
        yield i, j
      end
    end
    new rows, column_size
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
    rows = (0 ... size).collect {|j|
      row = Array.new(size).fill(0, 0, size)
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
    Matrix.diagonal(*Array.new(n).fill(value, 0, n))
  end

  #
  # Creates an +n+ by +n+ identity matrix.
  #   Matrix.identity(2)
  #     => 1 0
  #        0 1
  #
  def Matrix.identity(n)
    Matrix.scalar(n, 1)
  end
  class << Matrix
    alias unit identity
    alias I identity
  end

  #
  # Creates an +n+ by +n+ zero matrix.
  #   Matrix.zero(2)
  #     => 0 0
  #        0 0
  #
  def Matrix.zero(n)
    Matrix.scalar(n, 0)
  end

  #
  # Creates a single-row matrix where the values of that row are as given in
  # +row+.
  #   Matrix.row_vector([4,5,6])
  #     => 4 5 6
  #
  def Matrix.row_vector(row)
    row = Matrix.convert_to_array(row)
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
    column = Matrix.convert_to_array(column)
    new [column].transpose, 1
  end

  #
  # Creates a empty matrix of +row_size+ x +column_size+.
  # +row_size+ or +column_size+ must be 0.
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
  def Matrix.empty(row_size = 0, column_size = 0)
    Matrix.Raise ArgumentError, "One size must be 0" if column_size != 0 && row_size != 0
    Matrix.Raise ArgumentError, "Negative size" if column_size < 0 || row_size < 0

    new([[]]*row_size, column_size)
  end

  #
  # Matrix.new is private; use Matrix.rows, columns, [], etc... to create.
  #
  def initialize(rows, column_size = rows[0].size)
    # No checking is done at this point. rows must be an Array of Arrays.
    # column_size must be the size of the first row, if there is one,
    # otherwise it *must* be specified and can be any integer >= 0
    @rows = rows
    @column_size = column_size
  end

  def new_matrix(rows, column_size = rows[0].size) # :nodoc:
    Matrix.send(:new, rows, column_size) # bypass privacy of Matrix.new
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
  def row_size
    @rows.size
  end

  #
  # Returns the number of columns.
  #
  attr_reader :column_size

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
      return self if j >= column_size || j < -column_size
      row_size.times do |i|
        yield @rows[i][j]
      end
      self
    else
      return nil if j >= column_size || j < -column_size
      col = (0 ... row_size).collect {|i|
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
    new_matrix rows, column_size
  end
  alias map collect

  #
  # Yields all elements of the matrix, starting with those of the first row,
  # or returns an Enumerator is no block given
  #   Matrix[ [1,2], [3,4] ].each { |e| puts e }
  #     # => prints the numbers 1 to 4
  #
  def each(&block) # :yield: e
    return to_enum(:each) unless block_given?
    @rows.each do |row|
      row.each(&block)
    end
    self
  end

  #
  # Yields all elements of the matrix, starting with those of the first row,
  # along with the row index and column index,
  # or returns an Enumerator is no block given
  #   Matrix[ [1,2], [3,4] ].each_with_index do |e, row, col|
  #     puts "#{e} at #{row}, #{col}"
  #   end
  #     # => 1 at 0, 0
  #     # => 2 at 0, 1
  #     # => 3 at 1, 0
  #     # => 4 at 1, 1
  #
  def each_with_index(&block) # :yield: e, row, column
    return to_enum(:each_with_index) unless block_given?
    @rows.each_with_index do |row, row_index|
      row.each_with_index do |e, col_index|
        yield e, row_index, col_index
      end
    end
    self
  end

  #
  # Returns a section of the matrix.  The parameters are either:
  # *  start_row, nrows, start_col, ncols; OR
  # *  col_range, row_range
  #
  #   Matrix.diagonal(9, 5, -3).minor(0..1, 0..2)
  #     => 9 0 0
  #        0 5 0
  #
  # Like Array#[], negative indices count backward from the end of the
  # row or column (-1 is the last element). Returns nil if the starting
  # row or column is greater than row_size or column_size respectively.
  #
  def minor(*param)
    case param.size
    when 2
      from_row = param[0].first
      from_row += row_size if from_row < 0
      to_row = param[0].end
      to_row += row_size if to_row < 0
      to_row += 1 unless param[0].exclude_end?
      size_row = to_row - from_row
      from_col = param[1].first
      from_col += column_size if from_col < 0
      to_col = param[1].end
      to_col += column_size if to_col < 0
      to_col += 1 unless param[1].exclude_end?
      size_col = to_col - from_col
    when 4
      from_row, size_row, from_col, size_col = param
      return nil if size_row < 0 || size_col < 0
      from_row += row_size if from_row < 0
      from_col += column_size if from_col < 0
    else
      Matrix.Raise ArgumentError, param.inspect
    end

    return nil if from_row > row_size || from_col > column_size || from_row < 0 || from_col < 0
    rows = @rows[from_row, size_row].collect{|row|
      row[from_col, size_col]
    }
    new_matrix rows, column_size - from_col
  end

  #--
  # TESTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns +true+ if this is an empty matrix, i.e. if the number of rows
  # or the number of columns is 0.
  #
  def empty?
    column_size == 0 || row_size == 0
  end

  #
  # Returns +true+ if all entries of the matrix are real.
  #
  def real?
    all?(&:real?)
  end

  #
  # Returns +true+ if this is a regular matrix.
  #
  def regular?
    square? and rank == column_size
  end

  #
  # Returns +true+ is this is a singular (i.e. non-regular) matrix.
  #
  def singular?
    not regular?
  end

  #
  # Returns +true+ is this is a square matrix.
  #
  def square?
    column_size == row_size
  end

  #--
  # OBJECT METHODS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns +true+ if and only if the two matrices contain equal elements.
  #
  def ==(other)
    return false unless Matrix === other
    rows == other.rows
  end

  def eql?(other)
    return false unless Matrix === other
    rows.eql? other.rows
  end

  #
  # Returns a clone of the matrix, so that the contents of each do not reference
  # identical objects.
  # There should be no good reason to do this since Matrices are immutable.
  #
  def clone
    new_matrix @rows.map{|row| row.dup}, column_size
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
        row.collect {|e|
          e * m
        }
      }
      return new_matrix rows, column_size
    when Vector
      m = Matrix.column_vector(m)
      r = self * m
      return r.column(0)
    when Matrix
      Matrix.Raise ErrDimensionMismatch if column_size != m.row_size

      rows = (0 ... row_size).collect {|i|
        (0 ... m.column_size).collect {|j|
          (0 ... column_size).inject(0) do |vij, k|
            vij + self[i, k] * m[k, j]
          end
        }
      }
      return new_matrix rows, m.column_size
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
      m = Matrix.column_vector(m)
    when Matrix
    else
      return apply_through_coercion(m, __method__)
    end

    Matrix.Raise ErrDimensionMismatch unless row_size == m.row_size and column_size == m.column_size

    rows = (0 ... row_size).collect {|i|
      (0 ... column_size).collect {|j|
        self[i, j] + m[i, j]
      }
    }
    new_matrix rows, column_size
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
      m = Matrix.column_vector(m)
    when Matrix
    else
      return apply_through_coercion(m, __method__)
    end

    Matrix.Raise ErrDimensionMismatch unless row_size == m.row_size and column_size == m.column_size

    rows = (0 ... row_size).collect {|i|
      (0 ... column_size).collect {|j|
        self[i, j] - m[i, j]
      }
    }
    new_matrix rows, column_size
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
        row.collect {|e|
          e / other
        }
      }
      return new_matrix rows, column_size
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
    Matrix.I(row_size).inverse_from(self)
  end
  alias inv inverse

  #
  # Not for public consumption?
  #
  def inverse_from(src)
    size = row_size
    a = src.to_a

    size.times do |k|
      i = k
      akk = a[k][k].abs
      (k+1 ... size).each do |j|
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

      size.times do |ii|
        next if ii == k
        q = a[ii][k].quo(akk)
        a[ii][k] = 0

        (k + 1 ... size).each do |j|
          a[ii][j] -= a[k][j] * q
        end
        size.times do |j|
          @rows[ii][j] -= @rows[k][j] * q
        end
      end

      (k + 1 ... size).each do |j|
        a[k][j] = a[k][j].quo(akk)
      end
      size.times do |j|
        @rows[k][j] = @rows[k][j].quo(akk)
      end
    end
    self
  end
  #alias reciprocal inverse

  #
  # Matrix exponentiation.  Defined for integer powers only.  Equivalent to
  # multiplying the matrix by itself N times.
  #   Matrix[[7,6], [3,9]] ** 2
  #     => 67 96
  #        48 99
  #
  def ** (other)
    if other.kind_of?(Integer)
      x = self
      if other <= 0
        x = self.inverse
        return Matrix.identity(self.column_size) if other == 0
        other = -other
      end
      z = nil
      loop do
        z = z ? z * x : x if other[0] == 1
        return z if (other >>= 1).zero?
        x *= x
      end
    elsif other.kind_of?(Float) || defined?(Rational) && other.kind_of?(Rational)
      Matrix.Raise ErrOperationNotImplemented, "**", self.class, other.class
    else
      Matrix.Raise ErrOperationNotDefined, "**", self.class, other.class
    end
  end

  #--
  # MATRIX FUNCTIONS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Returns the determinant of the matrix.
  # This method's algorithm is Gaussian elimination method
  # and using Numeric#quo(). Beware that using Float values, with their
  # usual lack of precision, can affect the value returned by this method.  Use
  # Rational values or Matrix#det_e instead if this is important to you.
  #
  #   Matrix[[7,6], [3,9]].determinant
  #     => 45.0
  #
  def determinant
    Matrix.Raise ErrDimensionMismatch unless square?

    size = row_size
    a = to_a

    det = 1
    size.times do |k|
      if (akk = a[k][k]) == 0
        i = (k+1 ... size).find {|ii|
          a[ii][k] != 0
        }
        return 0 if i.nil?
        a[i], a[k] = a[k], a[i]
        akk = a[k][k]
        det *= -1
      end

      (k + 1 ... size).each do |ii|
        q = a[ii][k].quo(akk)
        (k + 1 ... size).each do |j|
          a[ii][j] -= a[k][j] * q
        end
      end
      det *= akk
    end
    det
  end
  alias det determinant

  #
  # Returns the determinant of the matrix.
  # This method's algorithm is Gaussian elimination method.
  # This method uses Euclidean algorithm. If all elements are integer,
  # really exact value. But, if an element is a float, can't return
  # exact value.
  #
  #   Matrix[[7,6], [3,9]].determinant
  #     => 63
  #
  def determinant_e
    Matrix.Raise ErrDimensionMismatch unless square?

    size = row_size
    a = to_a

    det = 1
    size.times do |k|
      if a[k][k].zero?
        i = (k+1 ... size).find {|ii|
          a[ii][k] != 0
        }
        return 0 if i.nil?
        a[i], a[k] = a[k], a[i]
        det *= -1
      end

      (k + 1 ... size).each do |ii|
        q = a[ii][k].quo(a[k][k])
        (k ... size).each do |j|
          a[ii][j] -= a[k][j] * q
        end
        unless a[ii][k].zero?
          a[ii], a[k] = a[k], a[ii]
          det *= -1
          redo
        end
      end
      det *= a[k][k]
    end
    det
  end
  alias det_e determinant_e

  #
  # Returns the rank of the matrix. Beware that using Float values,
  # probably return faild value. Use Rational values or Matrix#rank_e
  # for getting exact result.
  #
  #   Matrix[[7,6], [3,9]].rank
  #     => 2
  #
  def rank
    if column_size > row_size
      a = transpose.to_a
      a_column_size = row_size
      a_row_size = column_size
    else
      a = to_a
      a_column_size = column_size
      a_row_size = row_size
    end
    rank = 0
    a_column_size.times do |k|
      if (akk = a[k][k]) == 0
        i = (k+1 ... a_row_size).find {|ii|
          a[ii][k] != 0
        }
        if i
          a[i], a[k] = a[k], a[i]
          akk = a[k][k]
        else
          i = (k+1 ... a_column_size).find {|ii|
            a[k][ii] != 0
          }
          next if i.nil?
          (k ... a_column_size).each do |j|
            a[j][k], a[j][i] = a[j][i], a[j][k]
          end
          akk = a[k][k]
        end
      end

      (k + 1 ... a_row_size).each do |ii|
        q = a[ii][k].quo(akk)
        (k + 1... a_column_size).each do |j|
          a[ii][j] -= a[k][j] * q
        end
      end
      rank += 1
    end
    return rank
  end

  #
  # Returns the rank of the matrix. This method uses Euclidean
  # algorithm. If all elements are integer, really exact value. But, if
  # an element is a float, can't return exact value.
  #
  #   Matrix[[7,6], [3,9]].rank
  #     => 2
  #
  def rank_e
    a = to_a
    a_column_size = column_size
    a_row_size = row_size
    pi = 0
    a_column_size.times do |j|
      if i = (pi ... a_row_size).find{|i0| !a[i0][j].zero?}
        if i != pi
          a[pi], a[i] = a[i], a[pi]
        end
        (pi + 1 ... a_row_size).each do |k|
          q = a[k][j].quo(a[pi][j])
          (pi ... a_column_size).each do |j0|
            a[k][j0] -= q * a[pi][j0]
          end
          if k > pi && !a[k][j].zero?
            a[k], a[pi] = a[pi], a[k]
            redo
          end
        end
        pi += 1
      end
    end
    pi
  end


  #
  # Returns the trace (sum of diagonal elements) of the matrix.
  #   Matrix[[7,6], [3,9]].trace
  #     => 16
  #
  def trace
    Matrix.Raise ErrDimensionMismatch unless square?
    (0...column_size).inject(0) do |tr, i|
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
    return Matrix.empty(column_size, 0) if row_size.zero?
    new_matrix @rows.transpose, row_size
  end
  alias t transpose

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
  # FIXME: describe #coerce.
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
    (0 ... row_size).collect {|i|
      row(i)
    }
  end

  #
  # Returns an array of the column vectors of the matrix.  See Vector.
  #
  def column_vectors
    (0 ... column_size).collect {|i|
      column(i)
    }
  end

  #
  # Returns an array of arrays that describe the rows of the matrix.
  #
  def to_a
    @rows.collect{|row| row.dup}
  end

  def elements_to_f
    warn "#{caller(1)[0]}: warning: Matrix#elements_to_f is deprecated"
    map(&:to_f)
  end

  def elements_to_i
    warn "#{caller(1)[0]}: warning: Matrix#elements_to_i is deprecated"
    map(&:to_i)
  end

  def elements_to_r
    warn "#{caller(1)[0]}: warning: Matrix#elements_to_r is deprecated"
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
      "Matrix.empty(#{row_size}, #{column_size})"
    else
      "Matrix[" + @rows.collect{|row|
        "[" + row.collect{|e| e.to_s}.join(", ") + "]"
      }.join(", ")+"]"
    end
  end

  #
  # Overrides Object#inspect
  #
  def inspect
    if empty?
      "Matrix.empty(#{row_size}, #{column_size})"
    else
      "Matrix#{@rows.inspect}"
    end
  end

  #
  # Converts the obj to an Array. If copy is set to true
  # a copy of obj will be made if necessary.
  #
  def Matrix.convert_to_array(obj, copy = false)
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

  # Private helper module

  module CoercionHelper # :nodoc:
    def apply_through_coercion(obj, oper)
      coercion = obj.coerce(self)
      raise TypeError unless coercion.is_a?(Array) && coercion.length == 2
      coercion[0].public_send(oper, coercion[1])
    rescue
      raise TypeError, "#{obj.inspect} can't be coerced into #{self.class}"
    end
    private :apply_through_coercion

    # Helper method to coerce a value into a specific class.
    # Raises a TypeError if the coercion fails or the returned value
    # is not of the right class.
    # (from Rubinius)
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

    def / (other)
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

    def ** (other)
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
# * <tt>  Vector.[](*array)                   </tt>
# * <tt>  Vector.elements(array, copy = true) </tt>
#
# To access elements:
# * <tt>  [](i)                               </tt>
#
# To enumerate the elements:
# * <tt> #each2(v)                            </tt>
# * <tt> #collect2(v)                         </tt>
#
# Vector arithmetic:
# * <tt>  *(x) "is matrix or number"          </tt>
# * <tt>  +(v)                                </tt>
# * <tt>  -(v)                                </tt>
#
# Vector functions:
# * <tt> #inner_product(v)                    </tt>
# * <tt> #collect                             </tt>
# * <tt> #map                                 </tt>
# * <tt> #map2(v)                             </tt>
# * <tt> #r                                   </tt>
# * <tt> #size                                </tt>
#
# Conversion to other data types:
# * <tt> #covector                            </tt>
# * <tt> #to_a                                </tt>
# * <tt> #coerce(other)                       </tt>
#
# String representations:
# * <tt> #to_s                                </tt>
# * <tt> #inspect                             </tt>
#
class Vector
  include ExceptionForMatrix
  include Enumerable
  include Matrix::CoercionHelper
  #INSTANCE CREATION

  private_class_method :new
  attr_reader :elements
  protected :elements
  #
  # Creates a Vector from a list of elements.
  #   Vector[7, 4, ...]
  #
  def Vector.[](*array)
    new Matrix.convert_to_array(array, copy = false)
  end

  #
  # Creates a vector from an Array.  The optional second argument specifies
  # whether the array itself or a copy is used internally.
  #
  def Vector.elements(array, copy = true)
    new Matrix.convert_to_array(array, copy)
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
    size.times.collect do |i|
      yield @elements[i], v[i]
    end
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
  # Return a copy of the vector.
  #
  def clone
    Vector.elements(@elements)
  end

  #
  # Return a hash-code for the vector.
  #
  def hash
    @elements.hash
  end

  #--
  # ARITHMETIC -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

  #
  # Multiplies the vector by +x+, where +x+ is a number or another vector.
  #
  def *(x)
    case x
    when Numeric
      els = @elements.collect{|e| e * x}
      Vector.elements(els, false)
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
      Vector.elements(els, false)
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
      Vector.elements(els, false)
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
      Vector.elements(els, false)
    when Matrix, Vector
      Vector.Raise ErrOperationNotDefined, "/", self.class, x.class
    else
      apply_through_coercion(x, __method__)
    end
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
      p += v1 * v2
    }
    p
  end

  #
  # Like Array#collect.
  #
  def collect(&block) # :yield: e
    return to_enum(:collect) unless block_given?
    els = @elements.collect(&block)
    Vector.elements(els, false)
  end
  alias map collect

  #
  # Like Vector#collect2, but returns a Vector instead of an Array.
  #
  def map2(v, &block) # :yield: e1, e2
    return to_enum(:map2, v) unless block_given?
    els = collect2(v, &block)
    Vector.elements(els, false)
  end

  #
  # Returns the modulus (Pythagorean distance) of the vector.
  #   Vector[5,8,2].r => 9.643650761
  #
  def r
    Math.sqrt(@elements.inject(0) {|v, e| v + e*e})
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
  # FIXME: describe Vector#coerce.
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
    str = "Vector"+@elements.inspect
  end
end

# Documentation comments:
#  - Matrix#coerce and Vector#coerce need to be documented
