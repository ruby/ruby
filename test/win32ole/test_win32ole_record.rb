# coding: us-ascii
# frozen_string_literal: false

begin
  require 'win32ole'
rescue LoadError
end
require 'test/unit'

PROGID_RBCOMTEST='RbComTest.ComSrvTest'

=begin
RbComTest.ComSrvTest is following VB.NET COM server(RbComTest solution).
(You must check COM interoperability.)

Imports System.Runtime.InteropServices
Public Class ComSrvTest
    <StructLayout(LayoutKind.Sequential)> _
    Public Structure Book
        <MarshalAs(UnmanagedType.BStr)> _
        Public title As String
        Public cost As Integer
    End Structure

    Public Function getBook() As Book
        Dim book As New Book
        book.title = "The Ruby Book"
        book.cost = 20
        Return book
    End Function

    Public Function getBooks() As Book()
        Dim book() As Book = {New Book, New Book}
        book(0).title = "The CRuby Book"
        book(0).cost = 30
        book(1).title = "The JRuby Book"
        book(1).cost = 40
        Return book
    End Function

    Public Sub getBookByRefObject(ByRef obj As Object)
        Dim book As New Book
        book.title = "The Ruby Reference Book"
        book.cost = 50
        obj = book
    End Sub

    Public Function getVer2BookByValBook(<MarshalAs(UnmanagedType.Struct)> ByVal book As Book) As Book
        Dim ret As New Book
        ret.title = book.title + " ver2"
        ret.cost = book.cost * 1.1
        Return ret
    End Function

    Public Sub getBookByRefBook(<MarshalAs(UnmanagedType.LPStruct)> ByRef book As Book)
        book.title = "The Ruby Reference Book2"
        book.cost = 44
    End Sub

    Public Sub getVer3BookByRefBook(<MarshalAs(UnmanagedType.LPStruct)> ByRef book As Book)
        book.title += " ver3"
        book.cost *= 1.2
    End Sub
End Class
=end


if defined?(WIN32OLE::Record)
  def rbcomtest_exist?
    WIN32OLE.new(PROGID_RBCOMTEST)
    true
  rescue WIN32OLE::RuntimeError
    false
  end

  class TestWIN32OLE_RECORD_BY_RBCOMTEST < Test::Unit::TestCase
    unless rbcomtest_exist?
      def test_dummy_for_skip_message
        omit "#{PROGID_RBCOMTEST} for WIN32OLE::Record test is not installed"
      end
    else
      def setup
        @obj = WIN32OLE.new(PROGID_RBCOMTEST)
      end

      def test_s_new_from_win32ole
        rec = WIN32OLE::Record.new('Book', @obj)
        assert(rec)
        assert_instance_of(WIN32OLE::Record, rec)
      end

      def test_s_new_from_win32ole_typelib
        tlib = @obj.ole_typelib
        rec = WIN32OLE::Record.new('Book', tlib)
        assert(rec)
        assert_instance_of(WIN32OLE::Record, rec)
      end

      def test_s_new_raise
        assert_raise(WIN32OLE::RuntimeError) {
          WIN32OLE::Record.new('NonExistRecordName', @obj)
        }
        assert_raise(ArgumentError) {
          WIN32OLE::Record.new
        }
        assert_raise(ArgumentError) {
          WIN32OLE::Record.new('NonExistRecordName')
        }
      end

      def test_to_h
        rec = WIN32OLE::Record.new('Book', @obj)
        assert_equal({'title'=>nil, 'cost'=>nil}, rec.to_h)
      end

      def test_typename
        rec = WIN32OLE::Record.new('Book', @obj)
        assert_equal('Book', rec.typename)
      end

      def test_method_missing_getter
        rec = WIN32OLE::Record.new('Book', @obj)
        assert_equal(nil, rec.title)
        assert_raise(KeyError) {
          rec.non_exist_name
        }
      end

      def test_method_missing_setter
        rec = WIN32OLE::Record.new('Book', @obj)
        rec.title = "Ruby Book"
        assert_equal("Ruby Book", rec.title)
      end

      def test_get_record_from_comserver
        rec = @obj.getBook
        assert_instance_of(WIN32OLE::Record, rec)
        assert_equal("The Ruby Book", rec.title)
        assert_equal(20, rec.cost)
      end

      def test_get_record_array_from_comserver
        rec = @obj.getBooks
        assert_instance_of(Array, rec)
        assert_equal(2, rec.size)
        assert_instance_of(WIN32OLE::Record, rec[0])
        assert_equal("The CRuby Book", rec[0].title)
        assert_equal(30, rec[0].cost)
        assert_instance_of(WIN32OLE::Record, rec[1])
        assert_equal("The JRuby Book", rec[1].title)
        assert_equal(40, rec[1].cost)
      end

      def test_pass_record_parameter
        rec = WIN32OLE::Record.new('Book', @obj)
        rec.title = "Ruby Book"
        rec.cost = 60
        book = @obj.getVer2BookByValBook(rec)
        assert_equal("Ruby Book ver2", book.title)
        assert_equal(66, book.cost)
      end

      def test_pass_variant_parameter_byref
        obj = WIN32OLE::Variant.new(nil, WIN32OLE::VARIANT::VT_VARIANT|WIN32OLE::VARIANT::VT_BYREF)
        @obj.getBookByRefBook(obj)
        assert_instance_of(WIN32OLE::Record, obj.value)
        book = obj.value
        assert_equal("The Ruby Reference Book2", book.title)
        assert_equal(44, book.cost)
      end

      def test_pass_record_parameter_byref
        book = WIN32OLE::Record.new('Book', @obj)
        @obj.getBookByRefBook(book)
        assert_equal("The Ruby Reference Book2", book.title)
        assert_equal(44, book.cost)
      end

      def test_pass_and_get_record_parameter_byref
        book = WIN32OLE::Record.new('Book', @obj)
        book.title = "Ruby Book"
        book.cost = 60
        @obj.getVer3BookByRefBook(book)
        assert_equal("Ruby Book ver3", book.title)
        assert_equal(72, book.cost)
      end

      def test_ole_instance_variable_get
        obj = WIN32OLE::Record.new('Book', @obj)
        assert_equal(nil, obj.ole_instance_variable_get(:title))
        assert_equal(nil, obj.ole_instance_variable_get('title'))
      end

      def test_ole_instance_variable_set
        book = WIN32OLE::Record.new('Book', @obj)
        book.ole_instance_variable_set(:title, "Ruby Book")
        assert_equal("Ruby Book", book.title)
        book.ole_instance_variable_set('title', "Ruby Book2")
        assert_equal("Ruby Book2", book.title)
      end

      def test_inspect
        book = WIN32OLE::Record.new('Book', @obj)
        assert_equal(%q[#<WIN32OLE::Record(Book) {"title"=>nil, "cost"=>nil}>], book.inspect)
      end
    end
  end

end
