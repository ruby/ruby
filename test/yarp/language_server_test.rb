# frozen_string_literal: true

require_relative "yarp_test_helper"
require "yarp/language_server"

module YARP
  class LanguageServerTest < Test::Unit::TestCase
    module Request
      # Represents a hash pattern.
      class Shape
        attr_reader :values

        def initialize(values)
          @values = values
        end

        def ===(other)
          values.all? do |key, value|
            value == :any ? other.key?(key) : value === other[key]
          end
        end
      end

      # Represents an array pattern.
      class Tuple
        attr_reader :values

        def initialize(values)
          @values = values
        end

        def ===(other)
          values.each_with_index.all? { |value, index| value === other[index] }
        end
      end

      def self.[](value)
        case value
        when Array
          Tuple.new(value.map { |child| self[child] })
        when Hash
          Shape.new(value.transform_values { |child| self[child] })
        else
          value
        end
      end
    end

    class Initialize < Struct.new(:id)
      def to_hash
        { method: "initialize", id: id }
      end
    end

    class Shutdown < Struct.new(:id)
      def to_hash
        { method: "shutdown", id: id }
      end
    end

    class TextDocumentDidOpen < Struct.new(:uri, :text)
      def to_hash
        {
          method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, text: text } }
        }
      end
    end

    class TextDocumentDidChange < Struct.new(:uri, :text)
      def to_hash
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: uri },
            contentChanges: [{ text: text }]
          }
        }
      end
    end

    class TextDocumentDidClose < Struct.new(:uri)
      def to_hash
        {
          method: "textDocument/didClose",
          params: { textDocument: { uri: uri } }
        }
      end
    end

    class TextDocumentCodeAction < Struct.new(:id, :uri, :diagnostics)
      def to_hash
        {
          method: "textDocument/codeAction",
          id: id,
          params: {
            textDocument: { uri: uri },
            context: {
              diagnostics: diagnostics,
            },
          },
        }
      end
    end

    class TextDocumentDiagnostic < Struct.new(:id, :uri)
      def to_hash
        {
          method: "textDocument/diagnostic",
          id: id,
          params: {
            textDocument: { uri: uri },
          }
        }
      end
    end

    def test_reading_file
      Tempfile.create(%w[test- .rb]) do |file|
        file.write("class Foo; end")
        file.rewind

        responses = run_server([
          Initialize.new(1),
          Shutdown.new(3)
        ])

        shape = Request[[
          { id: 1, result: { capabilities: Hash } },
          { id: 3, result: {} }
        ]]

        assert_operator(shape, :===, responses)
      end
    end

    def test_clean_shutdown
      responses = run_server([Initialize.new(1), Shutdown.new(2)])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    def test_file_that_does_not_exist
      responses = run_server([
        Initialize.new(1),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    def test_code_action_request
      message = "this is an error"
      diagnostic = {
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        message: message,
        severity: 1,
      }
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          1 + (
        RUBY
        TextDocumentCodeAction.new(2, "file:///path/to/file.rb", [diagnostic]),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: [
            {
              title: "Report incorrect error: `#{message}`",
              kind: "quickfix",
              diagnostics: [diagnostic],
              command: {
                title: "Report incorrect error",
                command: "vscode.open",
                arguments: [String]
              }
            }
          ],
        },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert(responses.dig(1, :result, 0, :command, :arguments, 0).include?(URI.encode_www_form_component(message)))
    end

    def test_code_action_request_no_diagnostic
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          1 + (
        RUBY
        TextDocumentCodeAction.new(2, "file:///path/to/file.rb", []),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: [] },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    def test_code_action_request_no_content
      message = "this is an error"
      diagnostic = {
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
        message: message,
        severity: 1,
      }
      responses = run_server([
        Initialize.new(1),
        TextDocumentCodeAction.new(2, "file:///path/to/file.rb", [diagnostic]),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: nil },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    def test_diagnostics_request_error
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          1 + (
        RUBY
        TextDocumentDiagnostic.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: { kind: "full", items: [
          {
            range: {
              start: { line: Integer, character: Integer },
              end: { line: Integer, character: Integer }
            },
            message: String,
            severity: Integer
          },
        ] } },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert(responses.dig(1, :result, :items).count { |item| item[:severity] == 1 } > 0)
    end

    def test_diagnostics_request_warning
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          a/b /c
        RUBY
        TextDocumentDiagnostic.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: { kind: "full", items: [
          {
            range: {
              start: { line: Integer, character: Integer },
              end: { line: Integer, character: Integer }
            },
            message: String,
            severity: Integer
          },
        ] } },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert(responses.dig(1, :result, :items).count { |item| item[:severity] == 2 } > 0)
    end

    def test_diagnostics_request_nothing
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          a = 1
        RUBY
        TextDocumentDiagnostic.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: { kind: "full", items: [] } },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_equal(0, responses.dig(1, :result, :items).size)
    end

    def test_diagnostics_request_no_content
      responses = run_server([
        Initialize.new(1),
        TextDocumentDiagnostic.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: nil },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    private

    def write(content)
      request = content.to_hash.merge(jsonrpc: "2.0").to_json
      "Content-Length: #{request.bytesize}\r\n\r\n#{request}"
    end

    def read(content)
      [].tap do |messages|
        while (headers = content.gets("\r\n\r\n"))
          source = content.read(headers[/Content-Length: (\d+)/i, 1].to_i)
          messages << JSON.parse(source, symbolize_names: true)
        end
      end
    end

    def run_server(messages)
      input = StringIO.new(messages.map { |message| write(message) }.join)
      output = StringIO.new

      LanguageServer.new(
        input: input,
        output: output,
      ).run

      read(output.tap(&:rewind))
    end
  end
end
