require 'time'

class RDoc::Parser::ChangeLog < RDoc::Parser

  include RDoc::Parser::Text

  parse_files_matching(/(\/|\\|\A)ChangeLog[^\/\\]*\z/)

  def create_document groups
    doc = RDoc::Markup::Document.new
    doc.file = @top_level

    doc << RDoc::Markup::Heading.new(1, File.basename(@file_name))
    doc << RDoc::Markup::BlankLine.new

    groups.each do |day, entries|
      doc << RDoc::Markup::Heading.new(2, day)
      doc << RDoc::Markup::BlankLine.new

      doc.concat create_entries entries
    end

    doc
  end

  def create_entries entries
    out = []

    entries.each do |entry, items|
      out << RDoc::Markup::Heading.new(3, entry)
      out << RDoc::Markup::BlankLine.new

      out << create_items(items)
    end

    out
  end

  def create_items items
    list = RDoc::Markup::List.new :NOTE

    items.each do |item|
      title, body = item.split /:\s*/, 2
      paragraph = RDoc::Markup::Paragraph.new body
      list_item = RDoc::Markup::ListItem.new title, paragraph
      list << list_item
    end

    list
  end

  def group_entries entries
    entries.group_by do |title, body|
      Time.parse(title).strftime "%Y-%m-%d"
    end
  end

  def parse_entries
    entries = {}
    entry_name = nil
    entry_body = []

    @content.each_line do |line|
      case line
      when /^\w.*/ then
        entries[entry_name] = entry_body if entry_name

        entry_name = $&

        begin
          Time.parse entry_name
        rescue ArgumentError
          entry_name = nil
        end

        entry_body = []
      when /^(\t| {8})\*\s*(.*)/ then
        entry_body << $2
      when /^(\t| {8})\s*(.*)/ then
        continuation = $2
        next unless last = entry_body.last

        if last =~ /\s\z/ then
          last << continuation
        else
          last << ' ' << continuation
        end
      end
    end

    entries[entry_name] = entry_body if entry_name

    entries.delete nil

    entries
  end

  def scan
    entries = parse_entries
    grouped_entries = group_entries entries

    doc = create_document grouped_entries

    @top_level.comment = doc

    @top_level
  end

end

