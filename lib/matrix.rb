#!/usr/local/bin/ruby
#
#   matrix.rb - 
#   	$Release Version: 1.0$
#   	$Revision: 1.5 $
#   	$Date: 1998/07/14 14:35:18 $
#       Original Version from Smalltalk-80 version
#	   on July 23, 1985 at 8:37:17 am
#   	by Keiju ISHITSUKA
#
# --
#
#   Matrix[[1,2,3],
#	      :
#	   [3,4,5]]
#   Matrix[row0,
#          row1,
#	    :
#          rown]
#
#   column: 列
#   row:    行
#
# module ExceptionForMatrix::
#   Exceptions:
#	ErrDimensionMismatch
#	    行または列数が一致していない.
#	ErrNotRegular
#	    正則行列でない.
#	ErrOperationNotDefined
#	    その演算子はまだ定義されていない.
#
# class Matrix
#   include ExceptionForMatrix
#
#   Methods:
#   class methods:
#	Matrix.[](*rows)
#	    rowsで渡された行列を生成する. rowsは配列の配列
#	    Matrix[[11, 12], [21, 22]]
#	Matrix.rows(rows, copy = TRUE)
#	    rowsを行ベクトルの集合として行列を生成する. copy=FALSE の
#	    時はその配列をそのまま用いる.
#	Matrix.columns(columns)
#	    rowsを列ベクトルの集合として行列を生成する. 
#	Matrix.diagonal(*values)
#	    valuesを対角成分とした対角行列を生成する.
#	Matrix.scalar(n, value)
#	    valueを対角成分とするn次ののスカラー行列を生成する.
#	Matrix.identity(n)
#	Matrix.unit(n)
#	Matrix.I(n)
#	    n次の単位行列を生成する.
#	Matrix.zero(n)
#	    n次の0-行列を生成する.
#	Matrix.row_vector(row)
#	    rowを行ベクトルとする1-n行列を生成する. rowはVectorかArray
#	    が可能.
#	Matrix.column_vector(column)
#	    columnを列ベクトルとするn-1行列を生成する. rowはVectorかArray
#	    が可能.
#   accessing:
#	[](i, j)
#	    行列の(i, j)成分を返す.
#	row_size
#	    行数を返す.
#	column_size
#	    列数を返す.
#	row(i)
#	    i番目の行ベクトルを返す. イテレータとして使われた時は, 行
#	    ベクトルを順番にイテーレータブロックに渡す.
#	column(j)
#	    j番目の列ベクトルを返す. 列ベクトルを順番にイテーレータブ
#	    ロックに渡す. 
#	collect
#	map
#	    全ての要素をイテレートしその戻り値を値とする行列を新たに生
#	    成する.
#	minor(*param)
#	    マイナー行列を返す. パラメータとしては, 以下のパターンがあ
#	    る:
#	    1. from_row, row_size, from_col, size_col
#	    2. from_row..to_row, from_col..to_col
#   TESTING:
#	regular?
#	    正則かどうか?
#	singular?
#	    正則ではないかどうか?
#	square?
#	    正方行列かどうか?
#   ARITHMETIC:
#	*(m)
#	    乗法
#	+(m)
#	    加法
#	-(m)
#	    減法
#	/(m)
#	    self * m.inv
#	inverse
#	inv
#	    逆行列
#	**
#	    冪乗
#   Matrix functions:
#	determinant
#	det
#	    行列式
#	rank
#	    ランク
#	trace
#	tr
#	    トレース
#	transpose
#	t
#	    転置行列
#   CONVERTING:
#	coerce(other)
#	row_vectors
#	    rowベクトルの配列
#	column_vectors
#	    columベクトルの配列
#	to_a
#	    (2重)配列に変換
#	to_f
#	    各要素をFloatに変換
#	to_i
#	    各要素をIntegerに変換
#	to_r
#	    各要素をRationalに変換
#   PRINTING:
#	to_s
#	    文字列としての表現
#	inspect
#
# class Vector
#   include ExceptionForMatrix
#
#   INSTANCE CREATION:
#	Vector.[](*array)
#	Vector.elements(array, copy = TRUE)
#   ACCSESSING:
#	[](i)
#	size
#   ENUMRATIONS:
#	each2(v)
#	collect2(v)
#   ARITHMETIC:
#	*(x) "is matrix or number"
#	+(v)
#	-(v)
#   VECTOR FUNCTIONS:
#	inner_product(v)
#	collect
#	map
#	map2(v)
#	r
#   CONVERTING:
#	covector
#	to_a
#	to_f
#	to_i
#	to_r
#	coerce(other)
#   PRINTING:
#	to_s
#	inspect

require "e2mmap.rb"

module ExceptionForMatrix
  Exception2MessageMapper.extend_to(binding)
  
  def_e2message(TypeError, "wrong argument type %s (expected %s)")
  def_e2message(ArgumentError, "Wrong # of arguments(%d for %d)")
  
  def_exception("ErrDimensionMismatch", "\#{self.type} dimemsion mismatch")
  def_exception("ErrNotRegular", "Not Regular Matrix")
  def_exception("ErrOperationNotDefined", "This operation(%s) can\\'t defined")
end

class Matrix
  @RCS_ID='-$Id: matrix.rb,v 1.5 1998/07/14 14:35:18 keiju Exp keiju $-'

  include ExceptionForMatrix
  
  # instance creations
  private_class_method :new
  
  def Matrix.[](*rows)
    new(:init_rows, rows, FALSE)
  end
  
  def Matrix.rows(rows, copy = TRUE)
    new(:init_rows, rows, copy)
  end
  
  def Matrix.columns(columns)
    rows = (0 .. columns[0].size - 1).collect {
      |i|
      (0 .. columns.size - 1).collect {
	|j|
	columns[j][i]
      }
    }
    Matrix.rows(rows, FALSE)
  end
  
  def Matrix.diagonal(*values)
    size = values.size
    rows = (0 .. size  - 1).collect {
      |j|
      row = Array.new(size).fill(0, 0, size)
      row[j] = values[j]
      row
    }
    self
    rows(rows, FALSE)
  end
  
  def Matrix.scalar(n, value)
    Matrix.diagonal(*Array.new(n).fill(value, 0, n))
  end

  def Matrix.identity(n)
    Matrix.scalar(n, 1)
  end
  class << Matrix 
    alias unit identity
    alias I identity
  end
  
  def Matrix.zero(n)
    Matrix.scalar(n, 0)
  end
  
  def Matrix.row_vector(row)
    case row
    when Vector
      Matrix.rows([row.to_a], FALSE)
    when Array
      Matrix.rows([row.dup], FALSE)
    else
      Matrix.row([[row]], FALSE)
    end
  end
  
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

  # initializing
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
  
  #accessing
  def [](i, j)
    @rows[i][j]
  end

  def row_size
    @rows.size
  end
  
  def column_size
    @rows[0].size
  end

  def row(i)
    if iterator?
      for e in @rows[i]
	yield e

      end
    else
      Vector.elements(@rows[i])
    end
  end

  def column(j)
    if iterator?
      0.upto(row_size - 1) do
	|i|
	yield @rows[i][j]
      end
    else
      col = (0 .. row_size - 1).collect {
	|i|
	@rows[i][j]
      }
      Vector.elements(col, FALSE)
    end
  end
  
  def collect
    rows = @rows.collect{|row| row.collect{|e| yield e}}
    Matrix.rows(rows, FALSE)
  end
  alias map collect
  
  #
  # param:  (from_row, row_size, from_col, size_col)
  #	    (from_row..to_row, from_col..to_col)
  #
  def minor(*param)
    case param.size
    when 2
      from_row = param[0].first
      size_row = param[0].size
      from_col = param[1].first
      size_col = param[1].size
    when 4
      from_row = param[0]
      size_row = param[1]
      from_col = param[2]
      size_col = param[3]
    else
      Matrix.fail ArgumentError, param.inspect
    end
    
    rows = @rows[from_row, size_row].collect{
      |row|
      row[from_col, size_col]
    }
    Matrix.rows(rows, FALSE)
  end
  
  # TESTING
  def regular?
    square? and rank == column_size
  end
  
  def singular?
    not regular?
  end

  def square?
    column_size == row_size
  end
  
  # COMPARING
  def ==(other)
    return FALSE unless Matrix === other
    
    other.compare_by_row_vectors(@rows)
  end
  alias eqn? ==
  
  def compare_by_row_vectors(rows)
    return FALSE unless @rows.size == rows.size
    
    0.upto(@rows.size - 1) do
      |i|
      return FALSE unless @rows[i] == rows[i]
    end
    TRUE
  end
  
  def clone
    Matrix.rows(@rows)
  end
  
  def hash
    value = 0
    for row in @rows
      for e in row
	value ^= e.hash
      end
    end
    return value
  end
  
  # ARITHMETIC
  
  def *(m) #is matrix or vector or number"
    case(m)
    when Numeric
      rows = @rows.collect {
	|row|
	row.collect {
	  |e|
	  e * m
	}
      }
      return Matrix.rows(rows, FALSE)
    when Vector
      m = Matrix.column_vector(m)
      r = self * m
      return r.column(0)
    when Matrix
      Matrix.fail ErrDimensionMismatch if column_size != m.row_size
    
      rows = (0 .. row_size - 1).collect {
	|i|
	(0 .. m.column_size - 1).collect {
	  |j|
	  vij = 0
	  0.upto(column_size - 1) do
	    |k|
	    vij += self[i, k] * m[k, j]
	  end
	  vij
	}
      }
      return Matrix.rows(rows, FALSE)
    else
      x, y = m.coerce(self)
      return x * y
    end
  end
  
  def +(m)
    case m
    when Numeric
      Matrix.fail ErrOperationNotDefined, "+"
    when Vector
      m = Matrix.column_vector(m)
    when Matrix
    else
      x, y = m.coerce(self)
      return x + y
    end
    
    Matrix.fail ErrDimensionMismatch unless row_size == m.row_size and column_size == m.column_size
    
    rows = (0 .. row_size - 1).collect {
      |i|
      (0 .. column_size - 1).collect {
	|j|
	self[i, j] + m[i, j]
      }
    }
    Matrix.rows(rows, FALSE)
  end

  def -(m)
    case m
    when Numeric
      Matrix.fail ErrOperationNotDefined, "-"
    when Vector
      m = Matrix.column_vector(m)
    when Matrix
    else
      x, y = m.coerce(self)
      return x - y
    end
    
    Matrix.fail ErrDimensionMismatch unless row_size == m.row_size and column_size == m.column_size
    
    rows = (0 .. row_size - 1).collect {
      |i|
      (0 .. column_size - 1).collect {
	|j|
	self[i, j] - m[i, j]
      }
    }
    Matrix.rows(rows, FALSE)
  end
  
  def /(other)
    case other
    when Numeric
      rows = @rows.collect {
	|row|
	row.collect {
	  |e|
	  e / other
	}
      }
      return Matrix.rows(rows, FALSE)
    when Matrix
      return self * other.inverse
    else
      x, y = other.coerce(self)
      rerurn x / y
    end
  end

  def inverse
    Matrix.fail ErrDimensionMismatch unless square?
    Matrix.I(row_size).inverse_from(self)
  end
  alias inv inverse
  
  def inverse_from(src)
    size = row_size - 1
    a = src.to_a
    
    for k in 0..size
      if (akk = a[k][k]) == 0
	i = k
	begin
	  fail ErrNotRegular if (i += 1) > size
	end while a[i][k] == 0
	a[i], a[k] = a[k], a[i]
	@rows[i], @rows[k] = @rows[k], @rows[i]
	akk = a[k][k]
      end
      
      for i in 0 .. size
	continue if i == k
	q = a[i][k] / akk
	a[i][k] = 0
	
	(k + 1).upto(size) do	
	  |j|
	  a[i][j] -= a[k][j] * q
	end
	0.upto(size) do
	  |j|
	  @rows[i][j] -= @rows[k][j] * q
	end
      end
      
      (k + 1).upto(size) do
	|j|
	a[k][j] /= akk
      end
      0.upto(size) do
	|j|
	@rows[k][j] /= akk
      end
    end
    self
  end
  #alias reciprocal inverse
  
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
      fail ErrOperationNotDefined, "**"
    else
      fail ErrOperationNotDefined, "**"
    end
  end
  
  # Matrix functions
  
  def determinant
    return 0 unless square?
    
    size = row_size - 1
    a = to_a
    
    det = 1
    k = 0
    begin 
      if (akk = a[k][k]) == 0
	i = k
	begin
	  return 0 if (i += 1) > size
	end while a[i][k] == 0
	a[i], a[k] = a[k], a[i]
	akk = a[k][k]
      end
      (k + 1).upto(size) do
	|i|
	q = a[i][k] / akk
	(k + 1).upto(size) do
	  |j|
	  a[i][j] -= a[k][j] * q
	end
      end
      det *= akk
    end while (k += 1) <= size
    det
  end
  alias det determinant
	
  def rank
    if column_size > row_size
      a = transpose.to_a
    else
      a = to_a
    end
    rank = 0
    k = 0
    begin
      if (akk = a[k][k]) == 0
	i = -1
	nothing = FALSE
	begin
	  if (i += 1) > column_size - 1
	    nothing = TRUE
	    break
	  end
	end while a[i][k] == 0
	continue if nothing
	a[i], a[k] = a[k], a[i]
	akk = a[k][k]
      end
      (k + 1).upto(row_size - 1) do
	|i|
	q = a[i][k] / akk
	(k + 1).upto(column_size - 1) do
	  |j|
	  a[i][j] -= a[k][j] * q
	end
      end
      rank += 1
    end while (k += 1) <= column_size - 1
    return rank
  end

  def trace
    tr = 0
    0.upto(column_size - 1) do
      |i|
      tr += @rows[i][i]
    end
    tr
  end
  alias tr trace
  
  def transpose
    Matrix.columns(@rows)
  end
  alias t transpose
  
  # CONVERTING
  
  def coerce(other)
    case other
    when Numeric
      return Scalar.new(other), self
    end
  end

  def row_vectors
    rows = (0 .. column_size - 1).collect {
      |i|
      row(i)
    }
    rows
  end
  
  def column_vectors
    columns = (0 .. row_size - 1).collect {
      |i|
      column(i)
    }
    columns
  end
  
  def to_a
    @rows.collect{|row| row.collect{|e| e}}
  end
  
  def to_f
    collect{|e| e.to_f}
  end
  
  def to_i
    collect{|e| e.to_i}
  end
  
  def to_r
    collect{|e| e.to_r}
  end
  
  # PRINTING
  def to_s
    "Matrix[" + @rows.collect{
      |row|
      "[" + row.collect{|e| e.to_s}.join(", ") + "]"
    }.join(", ")+"]"
  end
  
  def inspect
    "Matrix"+@rows.inspect
  end
  
  # Private CLASS
  
  class Scalar < Numeric
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
	Scalar.fail WrongArgType, other.type, "Numeric or Scalar"
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
	Scalar.fail WrongArgType, other.type, "Numeric or Scalar"
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
	Scalar.fail WrongArgType, other.type, "Numeric or Scalar or Matrix"
      when Matrix
	self * _M.inverse
      else
	x, y = other.coerce(self)
	x / y
      end
    end
    
    def ** (other)
      case other
      when Numeric
	Scalar.new(@value ** other)
      when Vector
	Scalar.fail WrongArgType, other.type, "Numeric or Scalar or Matrix"
      when Matrix
	other.powered_by(self)
      else
	x, y = other.coerce(self)
	x ** y
      end
    end
  end
end

#----------------------------------------------------------------------
#
#    - 
#
#----------------------------------------------------------------------
class Vector
  include ExceptionForMatrix
  
  #INSTANCE CREATION
  
  private_class_method :new
  def Vector.[](*array)
    new(:init_elements, array, copy = FALSE)
  end
  
  def Vector.elements(array, copy = TRUE)
    new(:init_elements, array, copy)
  end
  
  def initialize(method, array, copy)
    self.send(method, array, copy)
  end
  
  def init_elements(array, copy)
    if copy
      @elements = array.dup
    else
      @elements = array
    end
  end
  
  # ACCSESSING
	 
  def [](i)
    @elements[i]
  end
  
  def size
    @elements.size
  end
  
  # ENUMRATIONS
  def each2(v)
    Vector.fail ErrDimensionMismatch if size != v.size
    0.upto(size - 1) do
      |i|
      yield @elements[i], v[i]
    end
  end
  
  def collect2(v)
    Vector.fail ErrDimensionMismatch if size != v.size
    (0 .. size - 1).collect do
      |i|
      yield @elements[i], v[i]
    end
  end

  # COMPARING
  def ==(other)
    return FALSE unless Vector === other
    
    other.compare_by(@elements)
  end
  alias eqn? ==
  
  def compare_by(elements)
    @elements == elements
  end
  
  def clone
    Vector.elements(@elements)
  end
  
  def hash
    @elements.hash
  end
  
  # ARITHMETIC
  
  def *(x) "is matrix or number"
    case x
    when Numeric
      els = @elements.collect{|e| e * x}
      Vector.elements(els, FALSE)
    when Matrix
      self.covector * x
    else
      s, x = X.corece(self)
      s * x
    end
  end

  def +(v)
    case v
    when Vector
      Vector.fail ErrDimensionMismatch if size != v.size
      els = collect2(v) {
	|v1, v2|
	v1 + v2
      }
      Vector.elements(els, FALSE)
    when Matrix
      Matrix.column_vector(self) + v
    else
      s, x = v.corece(self)
      s + x
    end
  end

  def -(v)
    case v
    when Vector
      Vector.fail ErrDimensionMismatch if size != v.size
      els = collect2(v) {
	|v1, v2|
	v1 - v2
      }
      Vector.elements(els, FALSE)
    when Matrix
      Matrix.column_vector(self) - v
    else
      s, x = v.corece(self)
      s - x
    end
  end
  
  # VECTOR FUNCTIONS
  
  def inner_product(v)
    Vector.fail ErrDimensionMismatch if size != v.size
    
    p = 0
    each2(v) {
      |v1, v2|
      p += v1 * v2
    }
    p
  end
  
  def collect
    els = @elements.collect {
      |v|
      yield v
    }
    Vector.elements(els, FALSE)
  end
  alias map collect
  
  def map2(v)
    els = collect2(v) {
      |v1, v2|
      yield v1, v2
    }
    Vector.elements(els, FALSE)
  end
  
  def r
    v = 0
    for e in @elements
      v += e*e
    end
    return Math.sqrt(v)
  end
  
  # CONVERTING
  def covector
    Matrix.row_vector(self)
  end
  
  def to_a
    @elements.dup
  end
  
  def to_f
    collect{|e| e.to_f}
  end
  
  def to_i
    collect{|e| e.to_i}
  end
  
  def to_r
    collect{|e| e.to_r}
  end
  
  def coerce(other)
    case other
    when Numeric
      return Scalar.new(other), self
    end
  end
  
  # PRINTING
  
  def to_s
    "Vector[" + @elements.join(", ") + "]"
  end
  
  def inspect
    str = "Vector"+@elements.inspect
  end
end

