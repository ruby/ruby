#!/usr/local/bin/ruby
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
  def_exception("ErrOperationNotDefined", "This operation(%s) can\\'t defined")
end

#
# The +Matrix+ class represents a mathematical matrix, and provides methods for creating
# special-case matrices (zero, identity, diagonal, singular, vector), operating on them
# arithmetically and algebraically, and determining their mathematical properties (trace, rank,
# inverse, determinant).
#
# Note that although matrices should theoretically be rectangular, this is not
# enforced by the class.
#
# Also note that the determinant of integer matrices may be incorrectly calculated unless you
# also <tt>require 'mathn'</tt>.  This may be fixed in the future.
#
# == Method Catalogue
#
# To create a matrix:
# * <tt> Matrix[*rows]                  </tt>
# * <tt> Matrix.[](*rows)               </tt>
# * <tt> Matrix.rows(rows, copy = true) </tt>
# * <tt> Matrix.columns(columns)        </tt>
# * <tt> Matrix.diagonal(*values)       </tt>
# * <tt> Matrix.scalar(n, value)        </tt>
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
# * <tt> #minor(*param)                 </tt>
#
# Properties of a matrix:
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
  include ExceptionForMatrix
  
  # instance creations
  private_class_method :new
  
  #
  # Creates a matrix where each argument is a row.
  #   Matrix[ [25, 93], [-1, 66] ]
  #      =>  25 93
  #          -1 66
  #
  def Matrix.[](*rows)
    new(:init_rows, rows, false)
  end
  
  #
  # Creates a matrix where +rows+ is an array of arrays, each of which is a row
  # to the matrix.  If the optional argument +copy+ is false, use the given
  # arrays as the internal structure of the matrix without copying.
  #   Matrix.rows([[25, 93], [-1, 66]])
  #      =>  25 93
  #          -1 66
  def Matrix.rows(rows, copy = true)
    new(:init_rows, rows, copy)
  end
  
  #
  # Creates a matrix using +columns+ as an array of column vectors.
  #   Matrix.columns([[25, 93], [-1, 66]])
  #      =>  25 -1
  #          93 66
  #
  #
  def Matrix.columns(columns)
    rows = (0 .. columns[0].size - 1).collect {|i|
      (0 .. columns.size - 1).collect {|j|
        columns[j][i]
      }
    }
    Matrix.rows(rows, false)
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
    rows = (0 .. size  - 1).collect {|j|
      row = Array.new(size).fill(0, 0, size)
      row[j] = values[j]
      row
    }
    rows(rows, false)
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
    case row
    when Vector
      Matrix.rows([row.to_a], false)
    when Array
      Matrix.rows([row.dup], false)
    else
      Matrix.rows([[row]], false)
    end
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
    case column
    when Vector
      Matrix.columns([column.to_a])
    when Array
      Matrix.columns([column])
    else
      Matrix.columns([[column]])
    end
  end

  #
  # This method is used by the other methods that create matrices, and is of no
  # use to general users.
  #
  def initialize(init_method, *argv)
    self.send(init_method, *argv)
  end
  
  def init_rows(rows, copy)
    if copy
      @rows = rows.collect{|row| row.dup}
    else
      @rows = rows
    end
    self
  end
  private :init_rows
  
  #
  # Returns element (+i+,+j+) of the matrix.  That is: row +i+, column +j+.
  #
  def [](i, j)
    @rows[i][j]
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
  # Returns the number of columns.  Note that it is possible to construct a
  # matrix with uneven columns (e.g. Matrix[ [1,2,3], [4,5] ]), but this is
  # mathematically unsound.  This method uses the first row to determine the
  # result.
  #
  def column_size
    @rows[0].size
  end

  #
  # Returns row vector number +i+ of the matrix as a Vector (starting at 0 like
  # an array).  When a block is given, the elements of that vector are iterated.
  #
  def row(i) # :yield: e
    if block_given?
      for e in @rows[i]
        yield e
      end
    else
      Vector.elements(@rows[i])
    end
  end

  #
  # Returns column vector number +j+ of the matrix as a Vector (starting at 0
  # like an array).  When a block is given, the elements of that vector are
  # iterated.
  #
  def column(j) # :yield: e
    if block_given?
      0.upto(row_size - 1) do |i|
        yield @rows[i][j]
      end
    else
      col = (0 .. row_size - 1).collect {|i|
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
  def collect # :yield: e
    rows = @rows.collect{|row| row.collect{|e| yield e}}
    Matrix.rows(rows, false)
  end
  alias map collect
  
  #
  # Returns a section of the matrix.  The parameters are either:
  # *  start_row, nrows, start_col, ncols; OR
  # *  col_range, row_range
  #
  #   Matrix.diagonal(9, 5, -3).minor(0..1, 0..2)
  #     => 9 0 0
  #        0 5 0
  #
  def minor(*param)
    case param.size
    when 2
      from_row = param[0].first
      size_row = param[0].end - from_row
      size_row += 1 unless param[0].exclude_end?
      from_col = param[1].first
      size_col = param[1].end - from_col
      size_col += 1 unless param[1].exclude_end?
    when 4
      from_row = param[0]
      size_row = param[1]
      from_col = param[2]
      size_col = param[3]
    else
      Matrix.Raise ArgumentError, param.inspect
    end
    
    rows = @rows[from_row, size_row].collect{|row|
      row[from_col, size_col]
    }
    Matrix.rows(rows, false)
  end
 
  #--
  # TESTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++

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
  # Returns +true+ is this is a square matrix.  See note in column_size about this
  # being unreliable, though.
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
    
    other.compare_by_row_vectors(@rows)
  end
  def eql?(other)
    return false unless Matrix === other
    
    other.compare_by_row_vectors(@rows, :eql?)
  end
  
  #
  # Not really intended for general consumption.
  #
  def compare_by_row_vectors(rows, comparison = :==)
    return false unless @rows.size == rows.size
    
    0.upto(@rows.size - 1) do |i|
      return false unless @rows[i].send(comparison, rows[i])
    end
    true
  end
  
  #
  # Returns a clone of the matrix, so that the contents of each do not reference
  # identical objects.
  #
  def clone
    Matrix.rows(@rows)
  end
  
  #
  # Returns a hash-code for the matrix.
  #
  def hash
    value = 0
    for row in @rows
      for e in row
        value ^= e.hash
      end
    end
    return value
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
      return Matrix.rows(rows, false)
    when Vector
      m = Matrix.column_vector(m)
      r = self * m
      return r.column(0)
    when Matrix
      Matrix.Raise ErrDimensionMismatch if column_size != m.row_size
    
      rows = (0 .. row_size - 1).collect {|i|
        (0 .. m.column_size - 1).collect {|j|
          vij = 0
          0.upto(column_size - 1) do |k|
            vij += self[i, k] * m[k, j]
          end
          vij
        }
      }
      return Matrix.rows(rows, false)
    else
      x, y = m.coerce(self)
      return x * y
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
      Matrix.Raise ErrOperationNotDefined, "+"
    when Vector
      m = Matrix.column_vector(m)
    when Matrix
    else
      x, y = m.coerce(self)
      return x + y
    end
    
    Matrix.Raise ErrDimensionMismatch unless row_size == m.row_size and column_size == m.column_size
    
    rows = (0 .. row_size - 1).collect {|i|
      (0 .. column_size - 1).collect {|j|
        self[i, j] + m[i, j]
      }
    }
    Matrix.rows(rows, false)
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
      Matrix.Raise ErrOperationNotDefined, "-"
    when Vector
      m = Matrix.column_vector(m)
    when Matrix
    else
      x, y = m.coerce(self)
      return x - y
    end
    
    Matrix.Raise ErrDimensionMismatch unless row_size == m.row_size and column_size == m.column_size
    
    rows = (0 .. row_size - 1).collect {|i|
      (0 .. column_size - 1).collect {|j|
        self[i, j] - m[i, j]
      }
    }
    Matrix.rows(rows, false)
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
      return Matrix.rows(rows, false)
    when Matrix
      return self * other.inverse
    else
      x, y = other.coerce(self)
      return x / y
    end
  end

  #
  # Returns the inverse of the matrix.
  #   Matrix[[1, 2], [2, 1]].inverse
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
    size = row_size - 1
    a = src.to_a
    
    for k in 0..size
      i = k
      akk = a[k][k].abs
      ((k+1)..size).each do |j|
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
      
      for i in 0 .. size
        next if i == k
        q = a[i][k].quo(akk)
        a[i][k] = 0
        
	for j in (k + 1).. size
          a[i][j] -= a[k][j] * q
        end
        for j in 0..size
          @rows[i][j] -= @rows[k][j] * q
        end
      end
      
      for j in (k + 1).. size
        a[k][j] = a[k][j].quo(akk)
      end
      for j in 0..size
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
      z = x
      n = other  - 1
      while n != 0
        while (div, mod = n.divmod(2)
               mod == 0)
          x = x * x
          n = div
        end
        z *= x
        n -= 1
      end
      z
    elsif other.kind_of?(Float) || defined?(Rational) && other.kind_of?(Rational)
      Matrix.Raise ErrOperationNotDefined, "**"
    else
      Matrix.Raise ErrOperationNotDefined, "**"
    end
  end
  
  #--
  # MATRIX FUNCTIONS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++
  
  #
  # Returns the determinant of the matrix.  If the matrix is not square, the
  # result is 0. This method's algorism is Gaussian elimination method
  # and using Numeric#quo(). Beware that using Float values, with their
  # usual lack of precision, can affect the value returned by this method.  Use
  # Rational values or Matrix#det_e instead if this is important to you.
  #
  #   Matrix[[7,6], [3,9]].determinant
  #     => 63.0
  #
  def determinant
    return 0 unless square?
    
    size = row_size - 1
    a = to_a
    
    det = 1
    k = 0
    loop do
      if (akk = a[k][k]) == 0
        i = k
        loop do
          return 0 if (i += 1) > size
          break unless a[i][k] == 0
        end
        a[i], a[k] = a[k], a[i]
        akk = a[k][k]
        det *= -1
      end

      for i in k + 1 .. size
        q = a[i][k].quo(akk)
        (k + 1).upto(size) do |j|
          a[i][j] -= a[k][j] * q
        end
      end
      det *= akk
      break unless (k += 1) <= size
    end
    det
  end
  alias det determinant

  #
  # Returns the determinant of the matrix.  If the matrix is not square, the
  # result is 0. This method's algorism is Gaussian elimination method. 
  # This method uses Euclidean algorism. If all elements are integer,
  # really exact value. But, if an element is a float, can't return
  # exact value.   
  #
  #   Matrix[[7,6], [3,9]].determinant
  #     => 63
  #
  def determinant_e
    return 0 unless square?
    
    size = row_size - 1
    a = to_a
    
    det = 1
    k = 0
    loop do
      if a[k][k].zero?
        i = k
        loop do
          return 0 if (i += 1) > size
          break unless a[i][k].zero?
        end
        a[i], a[k] = a[k], a[i]
        det *= -1
      end

      for i in (k + 1)..size
        q = a[i][k].quo(a[k][k])
        k.upto(size) do |j|
          a[i][j] -= a[k][j] * q
        end
        unless a[i][k].zero?
          a[i], a[k] = a[k], a[i]
          det *= -1
          redo
        end
      end
      det *= a[k][k]
      break unless (k += 1) <= size
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
    k = 0
    begin
      if (akk = a[k][k]) == 0
        i = k
        exists = true
        loop do
          if (i += 1) > a_row_size - 1
            exists = false
            break
          end
          break unless a[i][k] == 0
        end
        if exists
          a[i], a[k] = a[k], a[i]
          akk = a[k][k]
        else
          i = k
          exists = true
          loop do
            if (i += 1) > a_column_size - 1
              exists = false
              break
            end
            break unless a[k][i] == 0
          end
          if exists
            k.upto(a_row_size - 1) do |j|
              a[j][k], a[j][i] = a[j][i], a[j][k]
            end
            akk = a[k][k]
          else
            next
          end
        end
      end

      for i in (k + 1)..(a_row_size - 1)
        q = a[i][k].quo(akk)
	for j in (k + 1)..(a_column_size - 1)
          a[i][j] -= a[k][j] * q
        end
      end
      rank += 1
    end while (k += 1) <= a_column_size - 1
    return rank
  end

  #
  # Returns the rank of the matrix. This method uses Euclidean
  # algorism. If all elements are integer, really exact value. But, if
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
    (0 ... a_column_size).each do |j|
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
    tr = 0
    0.upto(column_size - 1) do |i|
      tr += @rows[i][i]
    end
    tr
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
    Matrix.columns(@rows)
  end
  alias t transpose
  
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
    rows = (0 .. row_size - 1).collect {|i|
      row(i)
    }
    rows
  end
  
  #
  # Returns an array of the column vectors of the matrix.  See Vector.
  #
  def column_vectors
    columns = (0 .. column_size - 1).collect {|i|
      column(i)
    }
    columns
  end
  
  #
  # Returns an array of arrays that describe the rows of the matrix.
  #
  def to_a
    @rows.collect{|row| row.collect{|e| e}}
  end
  
  def elements_to_f
    collect{|e| e.to_f}
  end
  
  def elements_to_i
    collect{|e| e.to_i}
  end
  
  def elements_to_r
    collect{|e| e.to_r}
  end
  
  #--
  # PRINTING -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
  #++
  
  #
  # Overrides Object#to_s
  #
  def to_s
    "Matrix[" + @rows.collect{|row|
      "[" + row.collect{|e| e.to_s}.join(", ") + "]"
    }.join(", ")+"]"
  end
  
  #
  # Overrides Object#inspect
  #
  def inspect
    "Matrix"+@rows.inspect
  end
  
  # Private CLASS
  
  class Scalar < Numeric # :nodoc:
    include ExceptionForMatrix
    
    def initialize(value)
      @value = value
    end
    
    # ARITHMETIC
    def +(other)
      case other
      when Numeric
        Scalar.new(@value + other)
      when Vector, Matrix
        Scalar.Raise WrongArgType, other.class, "Numeric or Scalar"
      when Scalar
        Scalar.new(@value + other.value)
      else
        x, y = other.coerce(self)
        x + y
      end
    end
    
    def -(other)
      case other
      when Numeric
        Scalar.new(@value - other)
      when Vector, Matrix
        Scalar.Raise WrongArgType, other.class, "Numeric or Scalar"
      when Scalar
        Scalar.new(@value - other.value)
      else
        x, y = other.coerce(self)
        x - y
      end
    end
    
    def *(other)
      case other
      when Numeric
        Scalar.new(@value * other)
      when Vector, Matrix
        other.collect{|e| @value * e}
      else
        x, y = other.coerce(self)
        x * y
      end
    end
    
    def / (other)
      case other
      when Numeric
        Scalar.new(@value / other)
      when Vector
        Scalar.Raise WrongArgType, other.class, "Numeric or Scalar or Matrix"
      when Matrix
	self * other.inverse
      else
        x, y = other.coerce(self)
        x.quo(y)
      end
    end
    
    def ** (other)
      case other
      when Numeric
        Scalar.new(@value ** other)
      when Vector
        Scalar.Raise WrongArgType, other.class, "Numeric or Scalar or Matrix"
      when Matrix
        other.powered_by(self)
      else
        x, y = other.coerce(self)
        x ** y
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
  
  #INSTANCE CREATION
  
  private_class_method :new

  #
  # Creates a Vector from a list of elements.
  #   Vector[7, 4, ...]
  #
  def Vector.[](*array)
    new(:init_elements, array, copy = false)
  end
  
  #
  # Creates a vector from an Array.  The optional second argument specifies
  # whether the array itself or a copy is used internally.
  #
  def Vector.elements(array, copy = true)
    new(:init_elements, array, copy)
  end
  
  #
  # For internal use.
  #
  def initialize(method, array, copy)
    self.send(method, array, copy)
  end
  
  #
  # For internal use.
  #
  def init_elements(array, copy)
    if copy
      @elements = array.dup
    else
      @elements = array
    end
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
  # Iterate over the elements of this vector and +v+ in conjunction.
  #
  def each2(v) # :yield: e1, e2
    Vector.Raise ErrDimensionMismatch if size != v.size
    0.upto(size - 1) do |i|
      yield @elements[i], v[i]
    end
  end
  
  #
  # Collects (as in Enumerable#collect) over the elements of this vector and +v+
  # in conjunction.
  #
  def collect2(v) # :yield: e1, e2
    Vector.Raise ErrDimensionMismatch if size != v.size
    (0 .. size - 1).collect do |i|
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
    
    other.compare_by(@elements)
  end
  def eql?(other)
    return false unless Vector === other
    
    other.compare_by(@elements, :eql?)
  end
  
  #
  # For internal use.
  #
  def compare_by(elements, comparison = :==)
    @elements.send(comparison, elements)
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
    else
      s, x = x.coerce(self)
      s * x
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
      s, x = v.coerce(self)
      s + x
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
      s, x = v.coerce(self)
      s - x
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
  def collect # :yield: e
    els = @elements.collect {|v|
      yield v
    }
    Vector.elements(els, false)
  end
  alias map collect
  
  #
  # Like Vector#collect2, but returns a Vector instead of an Array.
  #
  def map2(v) # :yield: e1, e2
    els = collect2(v) {|v1, v2|
      yield v1, v2
    }
    Vector.elements(els, false)
  end
  
  #
  # Returns the modulus (Pythagorean distance) of the vector.
  #   Vector[5,8,2].r => 9.643650761
  #
  def r
    v = 0
    for e in @elements
      v += e*e
    end
    return Math.sqrt(v)
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
    collect{|e| e.to_f}
  end
  
  def elements_to_i
    collect{|e| e.to_i}
  end
  
  def elements_to_r
    collect{|e| e.to_r}
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
