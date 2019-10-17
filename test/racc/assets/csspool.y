class CSSPool::CSS::Parser

token CHARSET_SYM IMPORT_SYM STRING SEMI IDENT S COMMA LBRACE RBRACE STAR HASH
token LSQUARE RSQUARE EQUAL INCLUDES DASHMATCH LPAREN RPAREN FUNCTION GREATER PLUS
token SLASH NUMBER MINUS LENGTH PERCENTAGE ANGLE TIME FREQ URI
token IMPORTANT_SYM MEDIA_SYM NOT ONLY AND NTH_PSEUDO_CLASS
token DOCUMENT_QUERY_SYM FUNCTION_NO_QUOTE
token TILDE
token PREFIXMATCH SUFFIXMATCH SUBSTRINGMATCH
token NOT_PSEUDO_CLASS
token KEYFRAMES_SYM
token MATCHES_PSEUDO_CLASS
token NAMESPACE_SYM
token MOZ_PSEUDO_ELEMENT
token RESOLUTION
token COLON
token SUPPORTS_SYM
token OR
token VARIABLE_NAME
token CALC_SYM
token FONTFACE_SYM
token UNICODE_RANGE
token RATIO

rule
  document
    : { @handler.start_document }
      stylesheet
      { @handler.end_document }
    ;
  stylesheet
    : charset stylesheet
    | import stylesheet
    | namespace stylesheet
    | charset
    | import
    | namespace
    | body
    |
    ;
  charset
    : CHARSET_SYM STRING SEMI { @handler.charset interpret_string(val[1]), {} }
    ;
  import
    : IMPORT_SYM import_location medium SEMI {
        @handler.import_style val[2], val[1]
      }
    | IMPORT_SYM import_location SEMI {
        @handler.import_style [], val[1]
      }
    ;
  import_location
    : import_location S
    | STRING { result = Terms::String.new interpret_string val.first }
    | URI { result = Terms::URI.new interpret_uri val.first }
    ;
  namespace
    : NAMESPACE_SYM ident import_location SEMI {
        @handler.namespace val[1], val[2]
      }
    | NAMESPACE_SYM import_location SEMI {
        @handler.namespace nil, val[1]
      }
    ;
  medium
    : medium COMMA IDENT {
        result = val[0] << MediaType.new(val[2])
      }
    | IDENT {
        result = [MediaType.new(val[0])]
      }
    ;
  media_query_list
    : media_query                           { result = MediaQueryList.new([ val[0] ]) }
    | media_query_list COMMA media_query    { result = val[0] << val[2] }
    |                                       { result = MediaQueryList.new }
    ;
  media_query
    : optional_only_or_not media_type optional_and_exprs   { result = MediaQuery.new(val[0], val[1], val[2]) }
    | media_expr optional_and_exprs                        { result = MediaQuery.new(nil, val[0], val[1]) }
    ;
  optional_only_or_not
    : ONLY                { result = :only }
    | NOT                 { result = :not }
    |                     { result = nil }
    ;
  media_type
    : IDENT               { result = MediaType.new(val[0]) }
    ;
  media_expr
    : LPAREN optional_space IDENT optional_space RPAREN                            { result = MediaType.new(val[2]) }
    | LPAREN optional_space IDENT optional_space COLON optional_space expr RPAREN  { result = MediaFeature.new(val[2], val[6][0]) }
    ;
  optional_space
    : S                 { result = val[0] }
    |                   { result = nil }
    ;
  optional_and_exprs
    : optional_and_exprs AND media_expr  { result = val[0] << val[2] }
    |                                    { result = [] }
    ;
  resolution
    : RESOLUTION {
        unit = val.first.gsub(/[\s\d.]/, '')
        number = numeric(val.first)
        result = Terms::Resolution.new(number, unit)
      }
    ;
  body
    : ruleset body
    | conditional_rule body
    | keyframes_rule body
    | fontface_rule body
    | ruleset
    | conditional_rule
    | keyframes_rule
    | fontface_rule
    ;
  conditional_rule
    : media
    | document_query
    | supports
    ;
  body_in_media
    : body
    | empty_ruleset
    ;
  media
    : start_media body_in_media RBRACE { @handler.end_media val.first }
    ;
  start_media
    : MEDIA_SYM media_query_list LBRACE {
        result = val[1]
        @handler.start_media result
      }
    ;
  document_query
    : start_document_query body RBRACE { @handler.end_document_query(before_pos(val), after_pos(val)) }
    | start_document_query RBRACE { @handler.end_document_query(before_pos(val), after_pos(val)) }
    ;
  start_document_query
    : start_document_query_pos url_match_fns LBRACE {
        @handler.start_document_query(val[1], after_pos(val))
      }
    ;
  start_document_query_pos
    : DOCUMENT_QUERY_SYM {
        @handler.node_start_pos = before_pos(val)
      }
    ;
  url_match_fns
    : url_match_fn COMMA url_match_fns {
        result = [val[0], val[2]].flatten
      }
    | url_match_fn {
        result = val
      }
    ;
  url_match_fn
    : function_no_quote
    | function
    | uri
    ;
  supports
    : start_supports body RBRACE { @handler.end_supports }
    | start_supports RBRACE { @handler.end_supports }
    ;
  start_supports
    : SUPPORTS_SYM supports_condition_root LBRACE {
        @handler.start_supports val[1]
      }
    ;
  supports_condition_root
    : supports_negation { result = val.join('') }
    | supports_conjunction_or_disjunction { result = val.join('') }
    | supports_condition_in_parens { result = val.join('') }
    ;
  supports_condition
    : supports_negation { result = val.join('') }
    | supports_conjunction_or_disjunction { result = val.join('') }
    | supports_condition_in_parens { result = val.join('') }
    ;
  supports_condition_in_parens
    : LPAREN supports_condition RPAREN { result = val.join('') }
    | supports_declaration_condition { result = val.join('') }
    ;
  supports_negation
    : NOT supports_condition_in_parens { result = val.join('') }
    ;
  supports_conjunction_or_disjunction
    : supports_conjunction
    | supports_disjunction
    ;
  supports_conjunction
    : supports_condition_in_parens AND supports_condition_in_parens { result = val.join('') }
    | supports_conjunction_or_disjunction AND supports_condition_in_parens { result = val.join('') }
    ;
  supports_disjunction
    : supports_condition_in_parens OR supports_condition_in_parens { result = val.join('') }
    | supports_conjunction_or_disjunction OR supports_condition_in_parens { result = val.join('') }
    ;
  supports_declaration_condition
    : LPAREN declaration_internal RPAREN { result = val.join('') }
    | LPAREN S declaration_internal RPAREN { result = val.join('') }
  ;
  keyframes_rule
    : start_keyframes_rule keyframes_blocks RBRACE
    | start_keyframes_rule RBRACE
    ;
  start_keyframes_rule
    : KEYFRAMES_SYM IDENT LBRACE {
        @handler.start_keyframes_rule val[1]
      }
    ;
  keyframes_blocks
    : keyframes_block keyframes_blocks
    | keyframes_block
    ;
  keyframes_block
    : start_keyframes_block declarations RBRACE { @handler.end_keyframes_block }
    | start_keyframes_block RBRACE { @handler.end_keyframes_block }
    ;
  start_keyframes_block
    : keyframes_selectors LBRACE {
        @handler.start_keyframes_block val[0]
      }
    ;
  keyframes_selectors
    | keyframes_selector COMMA keyframes_selectors {
         result = val[0] + ', ' + val[2]
      }
    | keyframes_selector
    ;
  keyframes_selector
    : IDENT
    | PERCENTAGE { result = val[0].strip }
    ;
  fontface_rule
    : start_fontface_rule declarations RBRACE { @handler.end_fontface_rule }
    | start_fontface_rule RBRACE { @handler.end_fontface_rule }
    ;
  start_fontface_rule
    : FONTFACE_SYM LBRACE {
        @handler.start_fontface_rule
      }
    ;
  ruleset
    : start_selector declarations RBRACE {
        @handler.end_selector val.first
      }
    | start_selector RBRACE {
        @handler.end_selector val.first
      }
    ;
  empty_ruleset
    : optional_space {
        start = @handler.start_selector([])
        @handler.end_selector(start)
      }
    ;
  start_selector
    : S start_selector { result = val.last }
    | selectors LBRACE {
        @handler.start_selector val.first
      }
    ;
  selectors
    : selector COMMA selectors
      {
        sel = Selector.new(val.first, {})
        result = [sel].concat(val[2])
      }
    | selector
      {
        result = [Selector.new(val.first, {})]
      }
    ;
  selector
    : simple_selector combinator selector
      {
        val.flatten!
        val[2].combinator = val.delete_at 1
        result = val
      }
    | simple_selector
    ;
  combinator
    : S       { result = :s }
    | GREATER { result = :> }
    | PLUS    { result = :+ }
    | TILDE   { result = :~ }
    ;
  simple_selector
    : element_name hcap {
        selector = val.first
        selector.additional_selectors = val.last
        result = [selector]
      }
    | element_name { result = val }
    | hcap
      {
        ss = Selectors::Simple.new nil, nil
        ss.additional_selectors = val.flatten
        result = [ss]
      }
    ;
  simple_selectors
    : simple_selector COMMA simple_selectors { result = [val[0], val[2]].flatten }
    | simple_selector
    ;
  ident_with_namespace
    : IDENT { result = [interpret_identifier(val[0]), nil] }
    | IDENT '|' IDENT { result = [interpret_identifier(val[2]), interpret_identifier(val[0])] }
    | '|' IDENT { result = [interpret_identifier(val[1]), nil] }
    | STAR '|' IDENT { result = [interpret_identifier(val[2]), '*'] }
    ;
  element_name
    : ident_with_namespace { result = Selectors::Type.new val.first[0], nil, val.first[1] }
    | STAR { result = Selectors::Universal.new val.first }
    | '|' STAR { result = Selectors::Universal.new val[1] }
    | STAR '|' STAR { result = Selectors::Universal.new val[2], nil, val[0] }
    | IDENT '|' STAR { result = Selectors::Universal.new val[2], nil, interpret_identifier(val[0]) }
    ;
  hcap
    : hash        { result = val }
    | class       { result = val }
    | attrib      { result = val }
    | pseudo      { result = val }
    | hash hcap   { result = val.flatten }
    | class hcap  { result = val.flatten }
    | attrib hcap { result = val.flatten }
    | pseudo hcap { result = val.flatten }
    ;
  hash
    : HASH {
        result = Selectors::Id.new interpret_identifier val.first.sub(/^#/, '')
      }
  class
    : '.' IDENT {
        result = Selectors::Class.new interpret_identifier val.last
      }
    ;
  attrib
    : LSQUARE ident_with_namespace EQUAL IDENT RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_identifier(val[3]),
          Selectors::Attribute::EQUALS,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace EQUAL STRING RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_string(val[3]),
          Selectors::Attribute::EQUALS,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace INCLUDES STRING RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_string(val[3]),
          Selectors::Attribute::INCLUDES,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace INCLUDES IDENT RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_identifier(val[3]),
          Selectors::Attribute::INCLUDES,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace DASHMATCH IDENT RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_identifier(val[3]),
          Selectors::Attribute::DASHMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace DASHMATCH STRING RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_string(val[3]),
          Selectors::Attribute::DASHMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace PREFIXMATCH IDENT RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_identifier(val[3]),
          Selectors::Attribute::PREFIXMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace PREFIXMATCH STRING RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_string(val[3]),
          Selectors::Attribute::PREFIXMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace SUFFIXMATCH IDENT RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_identifier(val[3]),
          Selectors::Attribute::SUFFIXMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace SUFFIXMATCH STRING RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_string(val[3]),
          Selectors::Attribute::SUFFIXMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace SUBSTRINGMATCH IDENT RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_identifier(val[3]),
          Selectors::Attribute::SUBSTRINGMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace SUBSTRINGMATCH STRING RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          interpret_string(val[3]),
          Selectors::Attribute::SUBSTRINGMATCH,
          val[1][1]
        )
      }
    | LSQUARE ident_with_namespace RSQUARE {
        result = Selectors::Attribute.new(
          val[1][0],
          nil,
          Selectors::Attribute::SET,
          val[1][1]
        )
      }
    ;
  pseudo
    : COLON IDENT {
        result = Selectors::pseudo interpret_identifier(val[1])
      }
    | COLON COLON IDENT {
        result = Selectors::PseudoElement.new(
          interpret_identifier(val[2])
        )
      }
    | COLON FUNCTION RPAREN {
        result = Selectors::PseudoClass.new(
          interpret_identifier(val[1].sub(/\($/, '')),
          ''
        )
      }
    | COLON FUNCTION IDENT RPAREN {
        result = Selectors::PseudoClass.new(
          interpret_identifier(val[1].sub(/\($/, '')),
          interpret_identifier(val[2])
        )
      }
    | COLON NOT_PSEUDO_CLASS simple_selector RPAREN {
        result = Selectors::PseudoClass.new(
          'not',
          val[2].first.to_s
        )
      }
    | COLON NTH_PSEUDO_CLASS {
        result = Selectors::PseudoClass.new(
          interpret_identifier(val[1].sub(/\(.*/, '')),
          interpret_identifier(val[1].sub(/.*\(/, '').sub(/\).*/, ''))
        )
      }
    | COLON MATCHES_PSEUDO_CLASS simple_selectors RPAREN {
        result = Selectors::PseudoClass.new(
          val[1].split('(').first.strip,
          val[2].join(', ')
        )
      }
    | COLON MOZ_PSEUDO_ELEMENT optional_space any_number_of_idents optional_space RPAREN {
        result = Selectors::PseudoElement.new(
          interpret_identifier(val[1].sub(/\($/, ''))
        )
      }
    | COLON COLON MOZ_PSEUDO_ELEMENT optional_space any_number_of_idents optional_space RPAREN {
        result = Selectors::PseudoElement.new(
          interpret_identifier(val[2].sub(/\($/, ''))
        )
      }
    ;
  any_number_of_idents
    :
    | multiple_idents
    ;
  multiple_idents
    : IDENT
    | IDENT COMMA multiple_idents
    ;
  # declarations can be separated by one *or more* semicolons. semi-colons at the start or end of a ruleset are also allowed
  one_or_more_semis
    : SEMI
    | SEMI one_or_more_semis
    ;
  declarations
    : declaration one_or_more_semis declarations
    | one_or_more_semis declarations
    | declaration one_or_more_semis
    | declaration
    | one_or_more_semis
    ;
  declaration
    : declaration_internal { @handler.property val.first }
    ;
  declaration_internal
    : property COLON expr prio
      { result = Declaration.new(val.first, val[2], val[3]) }
    | property COLON S expr prio
      { result = Declaration.new(val.first, val[3], val[4]) }
    | property S COLON expr prio
      { result = Declaration.new(val.first, val[3], val[4]) }
    | property S COLON S expr prio
      { result = Declaration.new(val.first, val[4], val[5]) }
    ;
  prio
    : IMPORTANT_SYM { result = true }
    |               { result = false }
    ;
  property
    : IDENT { result = interpret_identifier val[0] }
    | STAR IDENT { result = interpret_identifier val.join }
    | VARIABLE_NAME { result = interpret_identifier val[0] }
    ;
  operator
    : COMMA
    | SLASH
    | EQUAL
    ;
  expr
    : term operator expr {
        result = [val.first, val.last].flatten
        val.last.first.operator = val[1]
      }
    | term expr { result = val.flatten }
    | term      { result = val }
    ;
  term
    : ident
    | ratio
    | numeric
    | string
    | uri
    | hexcolor
    | calc
    | function
    | resolution
    | VARIABLE_NAME
    | uranges
    ;
  function
    : function S { result = val.first }
    | FUNCTION expr RPAREN {
        name = interpret_identifier val.first.sub(/\($/, '')
        if name == 'rgb'
          result = Terms::Rgb.new(*val[1])
        else
          result = Terms::Function.new name, val[1]
        end
      }
    | FUNCTION RPAREN {
        name = interpret_identifier val.first.sub(/\($/, '')
        result = Terms::Function.new name
      }
    ;
  function_no_quote
    : function_no_quote S { result = val.first }
    | FUNCTION_NO_QUOTE {
        parts = val.first.split('(')
        name = interpret_identifier parts.first
        result = Terms::Function.new(name, [Terms::String.new(interpret_string_no_quote(parts.last))])
      }
    ;
  uranges
    : UNICODE_RANGE COMMA uranges
    | UNICODE_RANGE
    ;
  calc
    : CALC_SYM calc_sum RPAREN optional_space {
       result = Terms::Math.new(val.first.split('(').first, val[1])
      }
    ;
  # plus and minus are supposed to have whitespace around them, per http://dev.w3.org/csswg/css-values/#calc-syntax, but the numbers are eating trailing whitespace, so we inject it back in
  calc_sum
    : calc_product
    | calc_product PLUS calc_sum { val.insert(1, ' '); result = val.join('') }
    | calc_product MINUS calc_sum { val.insert(1, ' '); result = val.join('') }
    ;
  calc_product
    : calc_value
    | calc_value optional_space STAR calc_value { result = val.join('') }
    | calc_value optional_space SLASH calc_value { result = val.join('') }
    ;
  calc_value
    : numeric { result = val.join('') }
    | function { result = val.join('') } # for var() variable references
    | LPAREN calc_sum RPAREN { result = val.join('') }
    ;
  hexcolor
    : hexcolor S { result = val.first }
    | HASH { result = Terms::Hash.new val.first.sub(/^#/, '') }
    ;
  uri
    : uri S { result = val.first }
    | URI { result = Terms::URI.new interpret_uri val.first }
    ;
  string
    : string S { result = val.first }
    | STRING { result = Terms::String.new interpret_string val.first }
    ;
  numeric
    : unary_operator numeric {
        result = val[1]
        val[1].unary_operator = val.first
      }
    | NUMBER {
        result = Terms::Number.new numeric val.first
      }
    | PERCENTAGE {
        result = Terms::Number.new numeric(val.first), nil, '%'
      }
    | LENGTH {
        unit    = val.first.gsub(/[\s\d.]/, '')
        result = Terms::Number.new numeric(val.first), nil, unit
      }
    | ANGLE {
        unit    = val.first.gsub(/[\s\d.]/, '')
        result = Terms::Number.new numeric(val.first), nil, unit
      }
    | TIME {
        unit    = val.first.gsub(/[\s\d.]/, '')
        result = Terms::Number.new numeric(val.first), nil, unit
      }
    | FREQ {
        unit    = val.first.gsub(/[\s\d.]/, '')
        result = Terms::Number.new numeric(val.first), nil, unit
      }
    ;
  ratio
    : RATIO {
        result = Terms::Ratio.new(val[0], val[1])
      }
    ;
  unary_operator
    : MINUS { result = :minus }
    | PLUS  { result = :plus }
    ;
  ident
    : ident S { result = val.first }
    | IDENT { result = Terms::Ident.new interpret_identifier val.first }
    ;

---- inner

def numeric thing
  thing = thing.gsub(/[^\d.]/, '')
  Integer(thing) rescue Float(thing)
end

def interpret_identifier s
  interpret_escapes s
end

def interpret_uri s
  interpret_escapes s.match(/^url\((.*)\)$/mui)[1].strip.match(/^(['"]?)((?:\\.|.)*)\1$/mu)[2]
end

def interpret_string_no_quote s
  interpret_escapes s.match(/^(.*)\)$/mu)[1].strip.match(/^(['"]?)((?:\\.|.)*)\1$/mu)[2]
end

def interpret_string s
  interpret_escapes s.match(/^(['"])((?:\\.|.)*)\1$/mu)[2]
end

def interpret_escapes s
  token_exp = /\\(?:([0-9a-fA-F]{1,6}(?:\r\n|\s)?)|(.))/mu
  return s.gsub(token_exp) do |escape_sequence|
    if !$1.nil?
      code = $1.chomp.to_i 16
      code = 0xFFFD if code > 0x10FFFF
      next [code].pack('U')
    end
    next '' if $2 == "\n"
    next $2
  end
end

# override racc's on_error so we can have context in our error messages
def on_error(t, val, vstack)
  errcontext = (@ss.pre_match[-10..-1] || @ss.pre_match) +
                @ss.matched + @ss.post_match[0..9]
  line_number = @ss.pre_match.lines.count
  raise ParseError, sprintf("parse error on value %s (%s) " +
                            "on line %s around \"%s\"",
                            val.inspect, token_to_str(t) || '?',
                            line_number, errcontext)
end

def before_pos(val)
  # don't include leading whitespace
  return current_pos - val.last.length + val.last[/\A\s*/].size
end

def after_pos(val)
  # don't include trailing whitespace
  return current_pos - val.last[/\s*\z/].size
end

# charpos will work with multibyte strings but is not available until ruby 2
def current_pos
  @ss.respond_to?('charpos') ? @ss.charpos : @ss.pos
end
