require File.expand_path('lib/helper', __dir__)

module Racc
  class TestSample < TestCase
    # working samples
    [
      {
        grammar_file: "array.y",
        parser_class: :ArrayParser,
        testcases: [
          { input: "[1]", expected: ["1"] },
          { input: "[1, 2]", expected: ["1", "2"] },
        ]
      },
      {
        grammar_file: "array2.y",
        parser_class: :ArrayParser2,
        testcases: [
          { input: "[1]", expected: ["1"] },
          { input: "[1, 2]", expected: ["1", "2"] },
        ]
      },
      {
        grammar_file: "calc.y",
        parser_class: :Calcp,
        testcases: [
          { input: "1", expected: 1 },
          { input: "10", expected: 10 },
          { input: "2 + 1", expected: 3 },
          { input: "2 - 1", expected: 1 },
          { input: "3 * 4", expected: 12 },
          { input: "4 / 2", expected: 2 },
          { input: "3 / 2", expected: 1 },
          { input: "2 + 3 * 4", expected: 14 },
          { input: "(2 + 3) * 4", expected: 20 },
          { input: "2 + (3 * 4)", expected: 14 },
        ]
      },
      {
        grammar_file: "hash.y",
        parser_class: :HashParser,
        testcases: [
          { input: "{}", expected: {} },
          { input: "{ a => b }", expected: { "a" => "b" } },
          { input: "{ a => b, 1 => 2 }", expected: { "a" => "b", "1" => "2" } },
        ]
      },
    ].each do |data|
      define_method "test_#{data[:grammar_file]}" do
        outfile = compile_sample(data[:grammar_file])

        load(outfile)

        parser_class = Object.const_get(data[:parser_class])
        data[:testcases].each do |testcase|
          input = testcase[:input]
          actual = parser_class.new.parse(input)
          expected = testcase[:expected]
          assert_equal(expected, actual, "expected #{expected} but got #{actual} when input is #{input}")
        end
      ensure
        remove_const_f(data[:parser_class])
      end
    end

    private

    # returns the generated file's path
    def compile_sample(yfile)
      file = File.basename(yfile, '.y')
      out = File.join(@OUT_DIR, file)
      ruby "-I#{LIB_DIR}", RACC, File.join(SAMPLE_DIR, yfile), "-o#{out}"
      out
    end

    def remove_const_f(const_name)
      Object.send(:remove_const, const_name) if Object.const_defined?(const_name, false)
    end
  end
end
