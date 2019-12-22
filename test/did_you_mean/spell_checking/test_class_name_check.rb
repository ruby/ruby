require_relative '../helper'

module ACRONYM
end

class Project
  def self.bo0k
    Bo0k
  end
end

class Book
  class TableOfContents; end

  def tableof_contents
    TableofContents
  end

  class Page
    def tableof_contents
      TableofContents
    end

    def self.tableof_contents
      TableofContents
    end
  end
end

class ClassNameCheckTest < Test::Unit::TestCase
  include DidYouMean::TestHelper

  def test_corrections
    error = assert_raise(NameError) { ::Bo0k }
    assert_correction "Book", error.corrections
  end

  def test_corrections_include_case_specific_class_name
    error = assert_raise(NameError) { ::Acronym }
    assert_correction "ACRONYM", error.corrections
  end

  def test_corrections_include_top_level_class_name
    error = assert_raise(NameError) { Project.bo0k }
    assert_correction "Book", error.corrections
  end

  def test_names_in_corrections_have_namespaces
    error = assert_raise(NameError) { ::Book::TableofContents }
    assert_correction "Book::TableOfContents", error.corrections
  end

  def test_corrections_candidates_for_names_in_upper_level_scopes
    error = assert_raise(NameError) { Book::Page.tableof_contents }
    assert_correction "Book::TableOfContents", error.corrections
  end

  def test_corrections_should_work_from_within_instance_method
    error = assert_raise(NameError) { ::Book.new.tableof_contents }
    assert_correction "Book::TableOfContents", error.corrections
  end

  def test_corrections_should_work_from_within_instance_method_on_nested_class
    error = assert_raise(NameError) { ::Book::Page.new.tableof_contents }
    assert_correction "Book::TableOfContents", error.corrections
  end

  def test_does_not_suggest_user_input
    error = assert_raise(NameError) { ::Book::Cover }

    # This is a weird require, but in a multi-threaded condition, a constant may
    # be loaded between when a NameError occurred and when the spell checker
    # attempts to find a possible suggestion. The manual require here simulates
    # a race condition a single test.
    require_relative '../fixtures/book'

    assert_empty error.corrections
  end
end
