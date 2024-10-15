# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class RelocationTest < TestCase
    def test_repository_filepath
      repository = Relocation.filepath(__FILE__).lines
      declaration = Prism.parse_file(__FILE__).value.statements.body[1]

      assert_equal 5, declaration.save(repository).start_line
    end

    def test_filepath
      repository = Relocation.filepath(__FILE__).filepath
      declaration = Prism.parse_file(__FILE__).value.statements.body[1]

      assert_equal __FILE__, declaration.save(repository).filepath
    end

    def test_lines
      source = "class Foo😀\nend"
      repository = Relocation.string(source).lines
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.save(repository)
      location_entry = declaration.save_location(repository)

      assert_equal 1, node_entry.start_line
      assert_equal 2, node_entry.end_line

      assert_equal 1, location_entry.start_line
      assert_equal 2, location_entry.end_line
    end

    def test_offsets
      source = "class Foo😀\nend"
      repository = Relocation.string(source).offsets
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.constant_path.save(repository)
      location_entry = declaration.constant_path.save_location(repository)

      assert_equal 6, node_entry.start_offset
      assert_equal 13, node_entry.end_offset

      assert_equal 6, location_entry.start_offset
      assert_equal 13, location_entry.end_offset
    end

    def test_character_offsets
      source = "class Foo😀\nend"
      repository = Relocation.string(source).character_offsets
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.constant_path.save(repository)
      location_entry = declaration.constant_path.save_location(repository)

      assert_equal 6, node_entry.start_character_offset
      assert_equal 10, node_entry.end_character_offset

      assert_equal 6, location_entry.start_character_offset
      assert_equal 10, location_entry.end_character_offset
    end

    def test_code_unit_offsets
      source = "class Foo😀\nend"
      repository = Relocation.string(source).code_unit_offsets(Encoding::UTF_16LE)
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.constant_path.save(repository)
      location_entry = declaration.constant_path.save_location(repository)

      assert_equal 6, node_entry.start_code_units_offset
      assert_equal 11, node_entry.end_code_units_offset

      assert_equal 6, location_entry.start_code_units_offset
      assert_equal 11, location_entry.end_code_units_offset
    end

    def test_columns
      source = "class Foo😀\nend"
      repository = Relocation.string(source).columns
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.constant_path.save(repository)
      location_entry = declaration.constant_path.save_location(repository)

      assert_equal 6, node_entry.start_column
      assert_equal 13, node_entry.end_column

      assert_equal 6, location_entry.start_column
      assert_equal 13, location_entry.end_column
    end

    def test_character_columns
      source = "class Foo😀\nend"
      repository = Relocation.string(source).character_columns
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.constant_path.save(repository)
      location_entry = declaration.constant_path.save_location(repository)

      assert_equal 6, node_entry.start_character_column
      assert_equal 10, node_entry.end_character_column

      assert_equal 6, location_entry.start_character_column
      assert_equal 10, location_entry.end_character_column
    end

    def test_code_unit_columns
      source = "class Foo😀\nend"
      repository = Relocation.string(source).code_unit_columns(Encoding::UTF_16LE)
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.constant_path.save(repository)
      location_entry = declaration.constant_path.save_location(repository)

      assert_equal 6, node_entry.start_code_units_column
      assert_equal 11, node_entry.end_code_units_column

      assert_equal 6, location_entry.start_code_units_column
      assert_equal 11, location_entry.end_code_units_column
    end

    def test_leading_comments
      source = "# leading\nclass Foo\nend"
      repository = Relocation.string(source).leading_comments
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.save(repository)
      location_entry = declaration.save_location(repository)

      assert_equal ["# leading"], node_entry.leading_comments.map(&:slice)
      assert_equal ["# leading"], location_entry.leading_comments.map(&:slice)
    end

    def test_trailing_comments
      source = "class Foo\nend\n# trailing"
      repository = Relocation.string(source).trailing_comments
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.save(repository)
      location_entry = declaration.save_location(repository)

      assert_equal ["# trailing"], node_entry.trailing_comments.map(&:slice)
      assert_equal ["# trailing"], location_entry.trailing_comments.map(&:slice)
    end

    def test_comments
      source = "# leading\nclass Foo\nend\n# trailing"
      repository = Relocation.string(source).comments
      declaration = Prism.parse(source).value.statements.body.first

      node_entry = declaration.save(repository)
      location_entry = declaration.save_location(repository)

      assert_equal ["# leading", "# trailing"], node_entry.comments.map(&:slice)
      assert_equal ["# leading", "# trailing"], location_entry.comments.map(&:slice)
    end

    def test_misconfiguration
      assert_raise Relocation::Repository::ConfigurationError do
        Relocation.string("").comments.leading_comments
      end

      assert_raise Relocation::Repository::ConfigurationError do
        Relocation.string("").comments.trailing_comments
      end

      assert_raise Relocation::Repository::ConfigurationError do
        Relocation.string("").code_unit_offsets(Encoding::UTF_8).code_unit_offsets(Encoding::UTF_16LE)
      end

      assert_raise Relocation::Repository::ConfigurationError do
        Relocation.string("").lines.lines
      end
    end

    def test_missing_values
      source = "class Foo; end"
      repository = Relocation.string(source).lines

      declaration = Prism.parse(source).value.statements.body.first
      entry = declaration.constant_path.save(repository)

      assert_raise Relocation::Entry::MissingValueError do
        entry.start_offset
      end
    end
  end
end
