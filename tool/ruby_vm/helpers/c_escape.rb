#! /your/favourite/path/to/ruby
# -*- Ruby -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2017 Urabe, Shyouhei.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

require 'securerandom'

module RubyVM::CEscape
  module_function

  # generate comment, with escaps.
  def commentify str
    return "/* #{str.b.gsub('*/', '*\\/').gsub('/*', '/\\*')} */"
  end

  # Mimic gensym of CL.
  def gensym prefix = 'gensym_'
    return as_tr_cpp "#{prefix}#{SecureRandom.uuid}"
  end

  # Mimic AS_TR_CPP() of autoconf.
  def as_tr_cpp name
    q = name.b
    q.gsub! %r/[^a-zA-Z0-9_]/m, '_'
    q.gsub! %r/_+/, '_'
    return q
  end

  # Section 6.10.4 of  ISO/IEC 9899:1999 specifies that the file  name used for
  # #line directive shall be a "character string literal".  So this is needed.
  #
  # I'm  not sure  how  many  chars are  allowed  here,  though.  The  standard
  # specifies 4095 chars at most, after string concatenation (section 5.2.4.1).
  # But it is easy to have a path that is longer than that.
  #
  # Here  we ignore  the standard.  Just create  single string  literal of  any
  # needed length.
  def rstring2cstr str
    # I believe this is the fastest implementation done in pure-ruby.
    # Constants cached, gsub skips block evaluation, string literal optimized.
    buf = str.b
    buf.gsub! %r/./nm, RString2CStr
    return %'"#{buf}"'
  end

  RString2CStr = {
      "\x00"=>  "\\0", "\x01"=> "\\x1", "\x02"=> "\\x2", "\x03"=> "\\x3",
      "\x04"=> "\\x4", "\x05"=> "\\x5", "\x06"=> "\\x6",   "\a"=>  "\\a",
        "\b"=>  "\\b",   "\t"=>  "\\t",   "\n"=>  "\\n",   "\v"=>  "\\v",
        "\f"=>  "\\f",   "\r"=>  "\\r", "\x0E"=> "\\xe", "\x0F"=> "\\xf",
      "\x10"=>"\\x10", "\x11"=>"\\x11", "\x12"=>"\\x12", "\x13"=>"\\x13",
      "\x14"=>"\\x14", "\x15"=>"\\x15", "\x16"=>"\\x16", "\x17"=>"\\x17",
      "\x18"=>"\\x18", "\x19"=>"\\x19", "\x1A"=>"\\x1a",   "\e"=>"\\x1b",
      "\x1C"=>"\\x1c", "\x1D"=>"\\x1d", "\x1E"=>"\\x1e", "\x1F"=>"\\x1f",
         " "=>    " ",    "!"=>    "!",   "\""=> "\\\"",    "#"=>    "#",
         "$"=>    "$",    "%"=>    "%",    "&"=>    "&",    "'"=>    "'",
         "("=>    "(",    ")"=>    ")",    "*"=>    "*",    "+"=>    "+",
         ","=>    ",",    "-"=>    "-",    "."=>    ".",    "/"=>    "/",
         "0"=>    "0",    "1"=>    "1",    "2"=>    "2",    "3"=>    "3",
         "4"=>    "4",    "5"=>    "5",    "6"=>    "6",    "7"=>    "7",
         "8"=>    "8",    "9"=>    "9",    ":"=>    ":",    ";"=>    ";",
         "<"=>    "<",    "="=>    "=",    ">"=>    ">",    "?"=>    "?",
         "@"=>    "@",    "A"=>    "A",    "B"=>    "B",    "C"=>    "C",
         "D"=>    "D",    "E"=>    "E",    "F"=>    "F",    "G"=>    "G",
         "H"=>    "H",    "I"=>    "I",    "J"=>    "J",    "K"=>    "K",
         "L"=>    "L",    "M"=>    "M",    "N"=>    "N",    "O"=>    "O",
         "P"=>    "P",    "Q"=>    "Q",    "R"=>    "R",    "S"=>    "S",
         "T"=>    "T",    "U"=>    "U",    "V"=>    "V",    "W"=>    "W",
         "X"=>    "X",    "Y"=>    "Y",    "Z"=>    "Z",    "["=>    "[",
        "\\"=> "\\\\",    "]"=>    "]",    "^"=>    "^",    "_"=>    "_",
         "`"=>    "`",    "a"=>    "a",    "b"=>    "b",    "c"=>    "c",
         "d"=>    "d",    "e"=>    "e",    "f"=>    "f",    "g"=>    "g",
         "h"=>    "h",    "i"=>    "i",    "j"=>    "j",    "k"=>    "k",
         "l"=>    "l",    "m"=>    "m",    "n"=>    "n",    "o"=>    "o",
         "p"=>    "p",    "q"=>    "q",    "r"=>    "r",    "s"=>    "s",
         "t"=>    "t",    "u"=>    "u",    "v"=>    "v",    "w"=>    "w",
         "x"=>    "x",    "y"=>    "y",    "z"=>    "z",    "{"=>    "{",
         "|"=>    "|",    "}"=>    "}",    "~"=>    "~", "\x7F"=>"\\x7f",
      "\x80"=>"\\x80", "\x81"=>"\\x81", "\x82"=>"\\x82", "\x83"=>"\\x83",
      "\x84"=>"\\x84", "\x85"=>"\\x85", "\x86"=>"\\x86", "\x87"=>"\\x87",
      "\x88"=>"\\x88", "\x89"=>"\\x89", "\x8A"=>"\\x8a", "\x8B"=>"\\x8b",
      "\x8C"=>"\\x8c", "\x8D"=>"\\x8d", "\x8E"=>"\\x8e", "\x8F"=>"\\x8f",
      "\x90"=>"\\x90", "\x91"=>"\\x91", "\x92"=>"\\x92", "\x93"=>"\\x93",
      "\x94"=>"\\x94", "\x95"=>"\\x95", "\x96"=>"\\x96", "\x97"=>"\\x97",
      "\x98"=>"\\x98", "\x99"=>"\\x99", "\x9A"=>"\\x9a", "\x9B"=>"\\x9b",
      "\x9C"=>"\\x9c", "\x9D"=>"\\x9d", "\x9E"=>"\\x9e", "\x9F"=>"\\x9f",
      "\xA0"=>"\\xa0", "\xA1"=>"\\xa1", "\xA2"=>"\\xa2", "\xA3"=>"\\xa3",
      "\xA4"=>"\\xa4", "\xA5"=>"\\xa5", "\xA6"=>"\\xa6", "\xA7"=>"\\xa7",
      "\xA8"=>"\\xa8", "\xA9"=>"\\xa9", "\xAA"=>"\\xaa", "\xAB"=>"\\xab",
      "\xAC"=>"\\xac", "\xAD"=>"\\xad", "\xAE"=>"\\xae", "\xAF"=>"\\xaf",
      "\xB0"=>"\\xb0", "\xB1"=>"\\xb1", "\xB2"=>"\\xb2", "\xB3"=>"\\xb3",
      "\xB4"=>"\\xb4", "\xB5"=>"\\xb5", "\xB6"=>"\\xb6", "\xB7"=>"\\xb7",
      "\xB8"=>"\\xb8", "\xB9"=>"\\xb9", "\xBA"=>"\\xba", "\xBB"=>"\\xbb",
      "\xBC"=>"\\xbc", "\xBD"=>"\\xbd", "\xBE"=>"\\xbe", "\xBF"=>"\\xbf",
      "\xC0"=>"\\xc0", "\xC1"=>"\\xc1", "\xC2"=>"\\xc2", "\xC3"=>"\\xc3",
      "\xC4"=>"\\xc4", "\xC5"=>"\\xc5", "\xC6"=>"\\xc6", "\xC7"=>"\\xc7",
      "\xC8"=>"\\xc8", "\xC9"=>"\\xc9", "\xCA"=>"\\xca", "\xCB"=>"\\xcb",
      "\xCC"=>"\\xcc", "\xCD"=>"\\xcd", "\xCE"=>"\\xce", "\xCF"=>"\\xcf",
      "\xD0"=>"\\xd0", "\xD1"=>"\\xd1", "\xD2"=>"\\xd2", "\xD3"=>"\\xd3",
      "\xD4"=>"\\xd4", "\xD5"=>"\\xd5", "\xD6"=>"\\xd6", "\xD7"=>"\\xd7",
      "\xD8"=>"\\xd8", "\xD9"=>"\\xd9", "\xDA"=>"\\xda", "\xDB"=>"\\xdb",
      "\xDC"=>"\\xdc", "\xDD"=>"\\xdd", "\xDE"=>"\\xde", "\xDF"=>"\\xdf",
      "\xE0"=>"\\xe0", "\xE1"=>"\\xe1", "\xE2"=>"\\xe2", "\xE3"=>"\\xe3",
      "\xE4"=>"\\xe4", "\xE5"=>"\\xe5", "\xE6"=>"\\xe6", "\xE7"=>"\\xe7",
      "\xE8"=>"\\xe8", "\xE9"=>"\\xe9", "\xEA"=>"\\xea", "\xEB"=>"\\xeb",
      "\xEC"=>"\\xec", "\xED"=>"\\xed", "\xEE"=>"\\xee", "\xEF"=>"\\xef",
      "\xF0"=>"\\xf0", "\xF1"=>"\\xf1", "\xF2"=>"\\xf2", "\xF3"=>"\\xf3",
      "\xF4"=>"\\xf4", "\xF5"=>"\\xf5", "\xF6"=>"\\xf6", "\xF7"=>"\\xf7",
      "\xF8"=>"\\xf8", "\xF9"=>"\\xf9", "\xFA"=>"\\xfa", "\xFB"=>"\\xfb",
      "\xFC"=>"\\xfc", "\xFD"=>"\\xfd", "\xFE"=>"\\xfe", "\xFF"=>"\\xff",
  }.freeze
  private_constant :RString2CStr
end

unless defined? ''.b
  class String
    def b
      return dup.force_encoding 'binary'
    end
  end
end
