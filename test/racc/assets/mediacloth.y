# Copyright (c) 2006 Pluron Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# The parser for the MediaWiki language.
#
# Usage together with a lexer:
# inputFile = File.new("data/input1", "r")
# input = inputFile.read
# parser = MediaWikiParser.new
# parser.lexer = MediaWikiLexer.new
# parser.parse(input)

class MediaWikiParser

token TEXT BOLD_START BOLD_END ITALIC_START ITALIC_END LINK_START LINK_END LINKSEP
    INTLINK_START INTLINK_END INTLINKSEP RESOURCESEP CHAR_ENT
    PRE_START PRE_END PREINDENT_START PREINDENT_END
    SECTION_START SECTION_END HLINE SIGNATURE_NAME SIGNATURE_DATE SIGNATURE_FULL
    PARA_START PARA_END UL_START UL_END OL_START OL_END LI_START LI_END
    DL_START DL_END DT_START DT_END DD_START DD_END TAG_START TAG_END ATTR_NAME ATTR_VALUE
    TABLE_START TABLE_END ROW_START ROW_END HEAD_START HEAD_END CELL_START CELL_END
    KEYWORD TEMPLATE_START TEMPLATE_END CATEGORY PASTE_START PASTE_END


rule

wiki:
    repeated_contents
        {
            @nodes.push WikiAST.new(0, @wiki_ast_length)
            #@nodes.last.children.insert(0, val[0])
            #puts val[0]
            @nodes.last.children += val[0]
        }
    ;

contents:
      text
        {
            result = val[0]
        }
    | bulleted_list
        {
            result = val[0]
        }
    | numbered_list
        {
            result = val[0]
        }
    | dictionary_list
        {
            list = ListAST.new(@ast_index, @ast_length)
            list.list_type = :Dictionary
            list.children = val[0]
            result = list
        }
    | preformatted
        {
            result = val[0]
        }
    | section
        {
            result = val[0]
        }
    | tag
        {
            result = val[0]
        }
    | template
        {
            result = val[0]
        }
    | KEYWORD
        {
            k = KeywordAST.new(@ast_index, @ast_length)
            k.text = val[0]
            result = k
        }
    | PARA_START para_contents PARA_END
        {
            p = ParagraphAST.new(@ast_index, @ast_length)
            p.children = val[1]
            result = p
        }
    | LINK_START link_contents LINK_END
        {
            l = LinkAST.new(@ast_index, @ast_length)
            l.link_type = val[0]
            l.url = val[1][0]
            l.children += val[1][1..-1] if val[1].length > 1
            result = l
        }
    | PASTE_START para_contents PASTE_END
        {
            p = PasteAST.new(@ast_index, @ast_length)
            p.children = val[1]
            result = p
        }
    | INTLINK_START TEXT RESOURCESEP TEXT reslink_repeated_contents INTLINK_END
        {
            l = ResourceLinkAST.new(@ast_index, @ast_length)
            l.prefix = val[1]
            l.locator = val[3]
            l.children = val[4] unless val[4].nil? or val[4].empty?
            result = l
        }
    | INTLINK_START TEXT intlink_repeated_contents INTLINK_END
        {
            l = InternalLinkAST.new(@ast_index, @ast_length)
            l.locator = val[1]
            l.children = val[2] unless val[2].nil? or val[2].empty?
            result = l
        }
    | INTLINK_START CATEGORY TEXT cat_sort_contents INTLINK_END
        {
            l = CategoryAST.new(@ast_index, @ast_length)
            l.locator = val[2]
            l.sort_as = val[3]
            result = l
        }
    | INTLINK_START RESOURCESEP CATEGORY TEXT intlink_repeated_contents INTLINK_END
        {
            l = CategoryLinkAST.new(@ast_index, @ast_length)
            l.locator = val[3]
            l.children = val[4] unless val[4].nil? or val[4].empty?
            result = l
        }
    | table
    ;

para_contents:
        {
            result = nil
        }
    | repeated_contents
        {
            result = val[0]
        }
    ;

tag:
      TAG_START tag_attributes TAG_END
        {
            if val[0] != val[2]
                raise Racc::ParseError.new("XHTML end tag #{val[2]} does not match start tag #{val[0]}")
            end
            elem = ElementAST.new(@ast_index, @ast_length)
            elem.name = val[0]
            elem.attributes = val[1]
            result = elem
        }
    | TAG_START tag_attributes repeated_contents TAG_END
        {
            if val[0] != val[3]
                raise Racc::ParseError.new("XHTML end tag #{val[3]} does not match start tag #{val[0]}")
            end
            elem = ElementAST.new(@ast_index, @ast_length)
            elem.name = val[0]
            elem.attributes = val[1]
            elem.children += val[2]
            result = elem
        }
    ;

tag_attributes:
        {
            result = nil
        }
    | ATTR_NAME tag_attributes
        {
            attr_map = val[2] ? val[2] : {}
            attr_map[val[0]] = true
            result = attr_map
        }
    | ATTR_NAME ATTR_VALUE tag_attributes
        {
            attr_map = val[2] ? val[2] : {}
            attr_map[val[0]] = val[1]
            result = attr_map
        }
    ;


link_contents:
      TEXT
        {
            result = val
        }
    | TEXT LINKSEP link_repeated_contents
        {
            result = [val[0]]
            result += val[2]
        }
    ;


link_repeated_contents:
      repeated_contents
        {
            result = val[0]
        }
    | repeated_contents LINKSEP link_repeated_contents
        {
            result = val[0]
            result += val[2] if val[2]
        }
    ;


intlink_repeated_contents:
        {
            result = nil
        }
    | INTLINKSEP repeated_contents
        {
            result = val[1]
        }
    ;

cat_sort_contents:
        {
            result = nil
        }
    | INTLINKSEP TEXT
        {
            result = val[1]
        }
    ;

reslink_repeated_contents:
        {
            result = nil
        }
    | INTLINKSEP reslink_repeated_contents
        {
            result = val[1]
        }
    | INTLINKSEP repeated_contents reslink_repeated_contents
        {
            i = InternalLinkItemAST.new(@ast_index, @ast_length)
            i.children = val[1]
            result = [i]
            result += val[2] if val[2]
        }
    ;

repeated_contents: contents
        {
            result = []
            result << val[0]
        }
    | repeated_contents contents
        {
            result = []
            result += val[0]
            result << val[1]
        }
    ;

text: element
        {
            p = TextAST.new(@ast_index, @ast_length)
            p.formatting = val[0][0]
            p.contents = val[0][1]
            result = p
        }
    | formatted_element
        {
            result = val[0]
        }
    ;

table:
      TABLE_START table_contents TABLE_END
        {
            table = TableAST.new(@ast_index, @ast_length)
            table.children = val[1] unless val[1].nil? or val[1].empty?
            result = table
        }
    | TABLE_START TEXT table_contents TABLE_END
        {
            table = TableAST.new(@ast_index, @ast_length)
            table.options = val[1]
            table.children = val[2] unless val[2].nil? or val[2].empty?
            result = table
        }

table_contents:
        {
            result = nil
        }
    | ROW_START row_contents ROW_END table_contents
        {
            row = TableRowAST.new(@ast_index, @ast_length)
            row.children = val[1] unless val[1].nil? or val[1].empty?
            result = [row]
            result += val[3] unless val[3].nil? or val[3].empty?
        }
    | ROW_START TEXT row_contents ROW_END table_contents
        {
            row = TableRowAST.new(@ast_index, @ast_length)
            row.children = val[2] unless val[2].nil? or val[2].empty?
            row.options = val[1]
            result = [row]
            result += val[4] unless val[4].nil? or val[4].empty?
        }

row_contents:
        {
            result = nil
        }
    | HEAD_START HEAD_END row_contents
        {
            cell = TableCellAST.new(@ast_index, @ast_length)
            cell.type = :head
            result = [cell]
            result += val[2] unless val[2].nil? or val[2].empty?
        }
    | HEAD_START repeated_contents HEAD_END row_contents
        {
            cell = TableCellAST.new(@ast_index, @ast_length)
            cell.children = val[1] unless val[1].nil? or val[1].empty?
            cell.type = :head
            result = [cell]
            result += val[3] unless val[3].nil? or val[3].empty?
        }
    | CELL_START CELL_END row_contents
        {
            cell = TableCellAST.new(@ast_index, @ast_length)
            cell.type = :body
            result = [cell]
            result += val[2] unless val[2].nil? or val[2].empty?
        }
    | CELL_START repeated_contents CELL_END row_contents
        {
            if val[2] == 'attributes'
                result = []
            else
                cell = TableCellAST.new(@ast_index, @ast_length)
                cell.children = val[1] unless val[1].nil? or val[1].empty?
                cell.type = :body
                result = [cell]
            end
            result += val[3] unless val[3].nil? or val[3].empty?
            if val[2] == 'attributes' and val[3] and val[3].first.class == TableCellAST
                val[3].first.attributes = val[1]
            end
            result
        }


element:
      TEXT
        { return [:None, val[0]] }
    | HLINE
        { return [:HLine, val[0]] }
    | CHAR_ENT
        { return [:CharacterEntity, val[0]] }
    | SIGNATURE_DATE
        { return [:SignatureDate, val[0]] }
    | SIGNATURE_NAME
        { return [:SignatureName, val[0]] }
    | SIGNATURE_FULL
        { return [:SignatureFull, val[0]] }
    ;

formatted_element:
      BOLD_START BOLD_END
        {
            result = FormattedAST.new(@ast_index, @ast_length)
            result.formatting = :Bold
            result
        }
    | ITALIC_START ITALIC_END
        {
            result = FormattedAST.new(@ast_index, @ast_length)
            result.formatting = :Italic
            result
        }
    | BOLD_START repeated_contents BOLD_END
        {
            p = FormattedAST.new(@ast_index, @ast_length)
            p.formatting = :Bold
            p.children += val[1]
            result = p
        }
    | ITALIC_START repeated_contents ITALIC_END
        {
            p = FormattedAST.new(@ast_index, @ast_length)
            p.formatting = :Italic
            p.children += val[1]
            result = p
        }
    ;

bulleted_list: UL_START list_item list_contents UL_END
        {
            list = ListAST.new(@ast_index, @ast_length)
            list.list_type = :Bulleted
            list.children << val[1]
            list.children += val[2]
            result = list
        }
    ;

numbered_list: OL_START list_item list_contents OL_END
        {
            list = ListAST.new(@ast_index, @ast_length)
            list.list_type = :Numbered
            list.children << val[1]
            list.children += val[2]
            result = list
        }
    ;

list_contents:
        { result = [] }
    list_item list_contents
        {
            result << val[1]
            result += val[2]
        }
    |
        { result = [] }
    ;

list_item:
      LI_START LI_END
        {
            result = ListItemAST.new(@ast_index, @ast_length)
        }
    | LI_START repeated_contents LI_END
        {
            li = ListItemAST.new(@ast_index, @ast_length)
            li.children += val[1]
            result = li
        }
    ;

dictionary_list:
      DL_START dictionary_term dictionary_contents DL_END
        {
            result = [val[1]]
            result += val[2]
        }
    | DL_START dictionary_contents DL_END
        {
            result = val[1]
        }
    ;

dictionary_term:
      DT_START DT_END
        {
            result = ListTermAST.new(@ast_index, @ast_length)
        }
    | DT_START repeated_contents DT_END
        {
            term = ListTermAST.new(@ast_index, @ast_length)
            term.children += val[1]
            result = term
        }

dictionary_contents:
      dictionary_definition dictionary_contents
        {
            result = [val[0]]
            result += val[1] if val[1]
        }
    |
        {
            result = []
        }

dictionary_definition:
      DD_START DD_END
        {
            result = ListDefinitionAST.new(@ast_index, @ast_length)
        }
    | DD_START repeated_contents DD_END
        {
            term = ListDefinitionAST.new(@ast_index, @ast_length)
            term.children += val[1]
            result = term
        }

preformatted: PRE_START repeated_contents PRE_END
        {
            p = PreformattedAST.new(@ast_index, @ast_length)
            p.children += val[1]
            result = p
        }
        | PREINDENT_START repeated_contents PREINDENT_END
        {
            p = PreformattedAST.new(@ast_index, @ast_length)
            p.indented = true
            p.children += val[1]
            result = p
        }
    ;

section: SECTION_START repeated_contents SECTION_END
        { result = [val[1], val[0].length]
            s = SectionAST.new(@ast_index, @ast_length)
            s.children = val[1]
            s.level = val[0].length
            result = s
        }
    ;

template: TEMPLATE_START TEXT template_parameters TEMPLATE_END
        {
            t = TemplateAST.new(@ast_index, @ast_length)
            t.template_name = val[1]
            t.children = val[2] unless val[2].nil? or val[2].empty?
            result = t
        }
    ;

template_parameters:
        {
            result = nil
        }
        | INTLINKSEP TEXT template_parameters
        {
            p = TemplateParameterAST.new(@ast_index, @ast_length)
            p.parameter_value = val[1]
            result = [p]
            result += val[2] if val[2]
        }
        | INTLINKSEP template template_parameters
        {
            p = TemplateParameterAST.new(@ast_index, @ast_length)
            p.children << val[1]
            result = [p]
            result += val[2] if val[2]
        }
    ;

end

---- header ----
require 'mediacloth/mediawikiast'

---- inner ----

attr_accessor :lexer

def initialize
    @nodes = []
    @context = []
    @wiki_ast_length = 0
    super
end

#Tokenizes input string and parses it.
def parse(input)
    @yydebug=true
    lexer.tokenize(input)
    do_parse
    return @nodes.last
end

#Asks the lexer to return the next token.
def next_token
    token = @lexer.lex
    if token[0].to_s.upcase.include? "_START"
        @context << token[2..3]
    elsif token[0].to_s.upcase.include? "_END"
        @ast_index = @context.last[0]
        @ast_length = token[2] + token[3] - @context.last[0]
        @context.pop
    else
        @ast_index = token[2]
        @ast_length = token[3]
    end

    @wiki_ast_length += token[3]

    return token[0..1]
end
