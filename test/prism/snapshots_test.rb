# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class SnapshotsTest < TestCase
    # When we pretty-print the trees to compare against the snapshots, we want
    # to be certain that we print with the same external encoding. This is
    # because methods like Symbol#inspect take into account external encoding
    # and it could change how the snapshot is generated. On machines with
    # certain settings (like LANG=C or -Eascii-8bit) this could have been
    # changed. So here we're going to force it to be UTF-8 to keep the snapshots
    # consistent.
    def setup
      @previous_default_external = Encoding.default_external
      ignore_warnings { Encoding.default_external = Encoding::UTF_8 }
    end

    def teardown
      ignore_warnings { Encoding.default_external = @previous_default_external }
    end

    except = []

    # These fail on TruffleRuby due to a difference in Symbol#inspect:
    # :测试 vs :"测试"
    if RUBY_ENGINE == "truffleruby"
      except.push(
        "emoji_method_calls.txt",
        "seattlerb/bug202.txt",
        "seattlerb/magic_encoding_comment.txt"
      )
    end

    Fixture.each(except: except) do |fixture|
      define_method(fixture.test_name) { assert_snapshot(fixture) }
    end

    private

    def assert_snapshot(fixture)
      source = fixture.read

      result = Prism.parse(source, filepath: fixture.path)
      assert result.success?

      printed = PP.pp(result.value, +"", 79)
      snapshot = fixture.snapshot_path

      if File.exist?(snapshot)
        saved = File.read(snapshot)

        # If the snapshot file exists, but the printed value does not match the
        # snapshot, then update the snapshot file.
        if printed != saved
          File.write(snapshot, printed)
          warn("Updated snapshot at #{snapshot}.")
        end

        # If the snapshot file exists, then assert that the printed value
        # matches the snapshot.
        assert_equal(saved, printed)
      else
        # If the snapshot file does not yet exist, then write it out now.
        directory = File.dirname(snapshot)
        FileUtils.mkdir_p(directory) unless File.directory?(directory)

        File.write(snapshot, printed)
        warn("Created snapshot at #{snapshot}.")
      end
    end
  end
end
