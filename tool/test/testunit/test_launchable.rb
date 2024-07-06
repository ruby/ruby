# frozen_string_literal: false
require 'test/unit'
require 'tempfile'
require 'json'
require_relative '../../lib/test/unit/launchable'

class TestLaunchable < Test::Unit::TestCase
  def test_json_stream_writer
    Tempfile.create(['launchable-test-', '.json']) do |f|
      json_stream_writer = Launchable::JsonStreamWriter.new(f.path)
      json_stream_writer.write_array('testCases')
      json_stream_writer.write_object(
        {
          testPath: "file=test/test_a.rb#class=class1#testcase=testcase899",
          duration: 42,
          status: "TEST_FAILED",
          stdout: nil,
          stderr: nil,
          createdAt: "2021-10-05T12:34:00",
          data: {
            lineNumber: 1
          }
        }
      )
      json_stream_writer.write_object(
        {
          testPath: "file=test/test_a.rb#class=class1#testcase=testcase899",
          duration: 45,
          status: "TEST_PASSED",
          stdout: "This is stdout",
          stderr: "This is stderr",
          createdAt: "2021-10-05T12:36:00",
          data: {
            lineNumber: 10
          }
        }
      )
      json_stream_writer.close()
      expected = <<JSON
{
  "testCases": [
    {
      "testPath": "file=test/test_a.rb#class=class1#testcase=testcase899",
      "duration": 42,
      "status": "TEST_FAILED",
      "stdout": null,
      "stderr": null,
      "createdAt": "2021-10-05T12:34:00",
      "data": {
        "lineNumber": 1
      }
    },
    {
      "testPath": "file=test/test_a.rb#class=class1#testcase=testcase899",
      "duration": 45,
      "status": "TEST_PASSED",
      "stdout": "This is stdout",
      "stderr": "This is stderr",
      "createdAt": "2021-10-05T12:36:00",
      "data": {
        "lineNumber": 10
      }
    }
  ]
}
JSON
      assert_equal(expected, f.read)
    end
  end
end
