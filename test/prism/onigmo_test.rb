# frozen_string_literal: true

require_relative "test_helper"

begin
  require "onigmo"
rescue LoadError
  # In CRuby's CI, we're not going to test against the parser gem because we
  # don't want to have to install it. So in this case we'll just skip this test.
  return
end

module Prism
  class OnigmoTest < TestCase
    def test_ONIGERR_PARSE_DEPTH_LIMIT_OVER
      assert_error(%Q{#{"(" * 4096}a#{")" * 4096}}, "parse depth limit over")
    end

    def test_ONIGERR_EMPTY_CHAR_CLASS
      assert_error("[]", "empty char-class")
    end

    private

    def assert_error(source, message)
      result = Prism.parse(%Q{/#{source}/ =~ ""})

      assert result.failure?
      assert_equal message, result.errors.first.message

      error = assert_raise(ArgumentError) { Onigmo.parse(source) }
      assert_equal message, error.message
    end
  end
end

__END__
case ONIGERR_PREMATURE_END_OF_CHAR_CLASS:
  p = "premature end of char-class"; break;
case ONIGERR_END_PATTERN_AT_ESCAPE:
  p = "end pattern at escape"; break;
case ONIGERR_END_PATTERN_AT_META:
  p = "end pattern at meta"; break;
case ONIGERR_END_PATTERN_AT_CONTROL:
  p = "end pattern at control"; break;
case ONIGERR_META_CODE_SYNTAX:
  p = "invalid meta-code syntax"; break;
case ONIGERR_CONTROL_CODE_SYNTAX:
  p = "invalid control-code syntax"; break;
case ONIGERR_CHAR_CLASS_VALUE_AT_END_OF_RANGE:
  p = "char-class value at end of range"; break;
case ONIGERR_UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS:
  p = "unmatched range specifier in char-class"; break;
case ONIGERR_TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED:
  p = "target of repeat operator is not specified"; break;
case ONIGERR_TARGET_OF_REPEAT_OPERATOR_INVALID:
  p = "target of repeat operator is invalid"; break;
case ONIGERR_UNMATCHED_CLOSE_PARENTHESIS:
  p = "unmatched close parenthesis"; break;
case ONIGERR_END_PATTERN_WITH_UNMATCHED_PARENTHESIS:
  p = "end pattern with unmatched parenthesis"; break;
case ONIGERR_END_PATTERN_IN_GROUP:
  p = "end pattern in group"; break;
case ONIGERR_UNDEFINED_GROUP_OPTION:
  p = "undefined group option"; break;
case ONIGERR_INVALID_POSIX_BRACKET_TYPE:
  p = "invalid POSIX bracket type"; break;
case ONIGERR_INVALID_LOOK_BEHIND_PATTERN:
  p = "invalid pattern in look-behind"; break;
case ONIGERR_INVALID_REPEAT_RANGE_PATTERN:
  p = "invalid repeat range {lower,upper}"; break;
case ONIGERR_INVALID_CONDITION_PATTERN:
  p = "invalid conditional pattern"; break;
case ONIGERR_TOO_BIG_NUMBER:
  p = "too big number"; break;
case ONIGERR_TOO_BIG_NUMBER_FOR_REPEAT_RANGE:
  p = "too big number for repeat range"; break;
case ONIGERR_UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE:
  p = "upper is smaller than lower in repeat range"; break;
case ONIGERR_EMPTY_RANGE_IN_CHAR_CLASS:
  p = "empty range in char class"; break;
case ONIGERR_TOO_MANY_MULTI_BYTE_RANGES:
  p = "too many multibyte code ranges are specified"; break;
case ONIGERR_TOO_SHORT_MULTI_BYTE_STRING:
  p = "too short multibyte code string"; break;
case ONIGERR_INVALID_BACKREF:
  p = "invalid backref number/name"; break;
  case ONIGERR_NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED:
    p = "numbered backref/call is not allowed. (use name)"; break;
  case ONIGERR_TOO_SHORT_DIGITS:
    p = "too short digits"; break;
  case ONIGERR_TOO_LONG_WIDE_CHAR_VALUE:
    p = "too long wide-char value"; break;
  case ONIGERR_EMPTY_GROUP_NAME:
    p = "group name is empty"; break;
  case ONIGERR_INVALID_GROUP_NAME:
    p = "invalid group name <%n>"; break;
  case ONIGERR_INVALID_CHAR_IN_GROUP_NAME:
#ifdef USE_NAMED_GROUP
    p = "invalid char in group name <%n>"; break;
#else
    p = "invalid char in group number <%n>"; break;
#endif
case ONIGERR_UNDEFINED_NAME_REFERENCE:
  p = "undefined name <%n> reference"; break;
case ONIGERR_UNDEFINED_GROUP_REFERENCE:
  p = "undefined group <%n> reference"; break;
case ONIGERR_MULTIPLEX_DEFINED_NAME:
  p = "multiplex defined name <%n>"; break;
case ONIGERR_MULTIPLEX_DEFINITION_NAME_CALL:
  p = "multiplex definition name <%n> call"; break;
case ONIGERR_NEVER_ENDING_RECURSION:
  p = "never ending recursion"; break;
#ifdef USE_CAPTURE_HISTORY
case ONIGERR_GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY:
  p = "group number is too big for capture history"; break;
#endif
case ONIGERR_INVALID_CHAR_PROPERTY_NAME:
  p = "invalid character property name {%n}"; break;
case ONIGERR_TOO_MANY_CAPTURE_GROUPS:
  p = "too many capture groups are specified"; break;
case ONIGERR_INVALID_CODE_POINT_VALUE:
  p = "invalid code point value"; break;
case ONIGERR_TOO_BIG_WIDE_CHAR_VALUE:
  p = "too big wide-char value"; break;
case ONIGERR_NOT_SUPPORTED_ENCODING_COMBINATION:
  p = "not supported encoding combination"; break;
case ONIGERR_INVALID_COMBINATION_OF_OPTIONS:
  p = "invalid combination of options"; break;    
