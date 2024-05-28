# frozen_string_literal: false

require "irb"
require "rdoc"
require_relative "helper"

module TestIRB
  class InputMethodTest < TestCase
    def setup
      @conf_backup = IRB.conf.dup
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      save_encodings
    end

    def teardown
      IRB.conf.replace(@conf_backup)
      restore_encodings
      # Reset Reline configuration overridden by RelineInputMethod.
      Reline.instance_variable_set(:@core, nil)
    end
  end

  class RelineInputMethodTest < InputMethodTest
    def test_initialization
      Reline.completion_proc = nil
      Reline.dig_perfect_match_proc = nil
      IRB::RelineInputMethod.new(IRB::RegexpCompletor.new)

      assert_nil Reline.completion_append_character
      assert_equal '', Reline.completer_quote_characters
      assert_equal IRB::InputMethod::BASIC_WORD_BREAK_CHARACTERS, Reline.basic_word_break_characters
      assert_not_nil Reline.completion_proc
      assert_not_nil Reline.dig_perfect_match_proc
    end

    def test_initialization_without_use_autocomplete
      original_show_doc_proc = Reline.dialog_proc(:show_doc)&.dialog_proc
      empty_proc = Proc.new {}
      Reline.add_dialog_proc(:show_doc, empty_proc)

      IRB.conf[:USE_AUTOCOMPLETE] = false

      IRB::RelineInputMethod.new(IRB::RegexpCompletor.new)

      refute Reline.autocompletion
      assert_equal empty_proc, Reline.dialog_proc(:show_doc).dialog_proc
    ensure
      Reline.add_dialog_proc(:show_doc, original_show_doc_proc, Reline::DEFAULT_DIALOG_CONTEXT)
    end

    def test_initialization_with_use_autocomplete
      original_show_doc_proc = Reline.dialog_proc(:show_doc)&.dialog_proc
      empty_proc = Proc.new {}
      Reline.add_dialog_proc(:show_doc, empty_proc)

      IRB.conf[:USE_AUTOCOMPLETE] = true

      IRB::RelineInputMethod.new(IRB::RegexpCompletor.new)

      assert Reline.autocompletion
      assert_not_equal empty_proc, Reline.dialog_proc(:show_doc).dialog_proc
    ensure
      Reline.add_dialog_proc(:show_doc, original_show_doc_proc, Reline::DEFAULT_DIALOG_CONTEXT)
    end

    def test_initialization_with_use_autocomplete_but_without_rdoc
      original_show_doc_proc = Reline.dialog_proc(:show_doc)&.dialog_proc
      empty_proc = Proc.new {}
      Reline.add_dialog_proc(:show_doc, empty_proc)

      IRB.conf[:USE_AUTOCOMPLETE] = true

      without_rdoc do
        IRB::RelineInputMethod.new(IRB::RegexpCompletor.new)
      end

      assert Reline.autocompletion
      # doesn't register show_doc dialog
      assert_equal empty_proc, Reline.dialog_proc(:show_doc).dialog_proc
    ensure
      Reline.add_dialog_proc(:show_doc, original_show_doc_proc, Reline::DEFAULT_DIALOG_CONTEXT)
    end
  end

  class DisplayDocumentTest < InputMethodTest
    def setup
      super
      @driver = RDoc::RI::Driver.new(use_stdout: true)
    end

    def display_document(target, bind, driver = nil)
      input_method = IRB::RelineInputMethod.new(IRB::RegexpCompletor.new)
      input_method.instance_variable_set(:@rdoc_ri_driver, driver) if driver
      input_method.instance_variable_set(:@completion_params, ['', target, '', bind])
      input_method.display_document(target)
    end

    def test_perfectly_matched_namespace_triggers_document_display
      omit unless has_rdoc_content?

      out, err = capture_output do
        display_document("String", binding, @driver)
      end

      assert_empty(err)

      assert_include(out, " S\bSt\btr\bri\bin\bng\bg")
    end

    def test_perfectly_matched_multiple_namespaces_triggers_document_display
      result = nil
      out, err = capture_output do
        result = display_document("{}.nil?", binding, @driver)
      end

      assert_empty(err)

      # check if there're rdoc contents (e.g. CI doesn't generate them)
      if has_rdoc_content?
        # if there's rdoc content, we can verify by checking stdout
        # rdoc generates control characters for formatting method names
        assert_include(out, "P\bPr\bro\boc\bc.\b.n\bni\bil\bl?\b?") # Proc.nil?
        assert_include(out, "H\bHa\bas\bsh\bh.\b.n\bni\bil\bl?\b?") # Hash.nil?
      else
        # this is a hacky way to verify the rdoc rendering code path because CI doesn't have rdoc content
        # if there are multiple namespaces to be rendered, PerfectMatchedProc renders the result with a document
        # which always returns the bytes rendered, even if it's 0
        assert_equal(0, result)
      end
    end

    def test_not_matched_namespace_triggers_nothing
      result = nil
      out, err = capture_output do
        result = display_document("Stri", binding, @driver)
      end

      assert_empty(err)
      assert_empty(out)
      assert_nil(result)
    end

    def test_perfect_matching_stops_without_rdoc
      result = nil

      out, err = capture_output do
        without_rdoc do
          result = display_document("String", binding)
        end
      end

      assert_empty(err)
      assert_not_match(/from ruby core/, out)
      assert_nil(result)
    end

    def test_perfect_matching_handles_nil_namespace
      out, err = capture_output do
        # symbol literal has `nil` doc namespace so it's a good test subject
        assert_nil(display_document(":aiueo", binding, @driver))
      end

      assert_empty(err)
      assert_empty(out)
    end

    private

    def has_rdoc_content?
      File.exist?(RDoc::RI::Paths::BASE)
    end
  end
end
