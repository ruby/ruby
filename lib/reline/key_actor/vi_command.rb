module Reline::KeyActor
  VI_COMMAND_MAPPING = [
    #   0 ^@
    nil,
    #   1 ^A
    :ed_move_to_beg,
    #   2 ^B
    nil,
    #   3 ^C
    :ed_ignore,
    #   4 ^D
    :vi_end_of_transmission,
    #   5 ^E
    :ed_move_to_end,
    #   6 ^F
    nil,
    #   7 ^G
    nil,
    #   8 ^H
    :ed_prev_char,
    #   9 ^I
    nil,
    #  10 ^J
    :ed_newline,
    #  11 ^K
    :ed_kill_line,
    #  12 ^L
    :ed_clear_screen,
    #  13 ^M
    :ed_newline,
    #  14 ^N
    :ed_next_history,
    #  15 ^O
    :ed_ignore,
    #  16 ^P
    :ed_prev_history,
    #  17 ^Q
    :ed_ignore,
    #  18 ^R
    :vi_search_prev,
    #  19 ^S
    :ed_ignore,
    #  20 ^T
    :ed_transpose_chars,
    #  21 ^U
    :vi_kill_line_prev,
    #  22 ^V
    :ed_quoted_insert,
    #  23 ^W
    :ed_delete_prev_word,
    #  24 ^X
    nil,
    #  25 ^Y
    :em_yank,
    #  26 ^Z
    nil,
    #  27 ^[
    nil,
    #  28 ^\
    :ed_ignore,
    #  29 ^]
    nil,
    #  30 ^^
    nil,
    #  31 ^_
    nil,
    #  32 SPACE
    :ed_next_char,
    #  33 !
    nil,
    #  34 "
    nil,
    #  35 #
    :vi_comment_out,
    #  36 $
    :ed_move_to_end,
    #  37 %
    nil,
    #  38 &
    nil,
    #  39 '
    nil,
    #  40 (
    nil,
    #  41 )
    nil,
    #  42 *
    nil,
    #  43 +
    :ed_next_history,
    #  44 ,
    nil,
    #  45 -
    :ed_prev_history,
    #  46 .
    nil,
    #  47 /
    :vi_search_prev,
    #  48 0
    :vi_zero,
    #  49 1
    :ed_argument_digit,
    #  50 2
    :ed_argument_digit,
    #  51 3
    :ed_argument_digit,
    #  52 4
    :ed_argument_digit,
    #  53 5
    :ed_argument_digit,
    #  54 6
    :ed_argument_digit,
    #  55 7
    :ed_argument_digit,
    #  56 8
    :ed_argument_digit,
    #  57 9
    :ed_argument_digit,
    #  58 :
    nil,
    #  59 ;
    nil,
    #  60 <
    nil,
    #  61 =
    nil,
    #  62 >
    nil,
    #  63 ?
    :vi_search_next,
    #  64 @
    :vi_alias,
    #  65 A
    :vi_add_at_eol,
    #  66 B
    :vi_prev_big_word,
    #  67 C
    :vi_change_to_eol,
    #  68 D
    :ed_kill_line,
    #  69 E
    :vi_end_big_word,
    #  70 F
    :vi_prev_char,
    #  71 G
    :vi_to_history_line,
    #  72 H
    nil,
    #  73 I
    :vi_insert_at_bol,
    #  74 J
    :vi_join_lines,
    #  75 K
    :vi_search_prev,
    #  76 L
    nil,
    #  77 M
    nil,
    #  78 N
    nil,
    #  79 O
    nil,
    #  80 P
    :vi_paste_prev,
    #  81 Q
    nil,
    #  82 R
    nil,
    #  83 S
    nil,
    #  84 T
    :vi_to_prev_char,
    #  85 U
    nil,
    #  86 V
    nil,
    #  87 W
    :vi_next_big_word,
    #  88 X
    :ed_delete_prev_char,
    #  89 Y
    nil,
    #  90 Z
    nil,
    #  91 [
    nil,
    #  92 \
    nil,
    #  93 ]
    nil,
    #  94 ^
    :vi_first_print,
    #  95 _
    nil,
    #  96 `
    nil,
    #  97 a
    :vi_add,
    #  98 b
    :vi_prev_word,
    #  99 c
    :vi_change_meta,
    # 100 d
    :vi_delete_meta,
    # 101 e
    :vi_end_word,
    # 102 f
    :vi_next_char,
    # 103 g
    nil,
    # 104 h
    :ed_prev_char,
    # 105 i
    :vi_insert,
    # 106 j
    :ed_next_history,
    # 107 k
    :ed_prev_history,
    # 108 l
    :ed_next_char,
    # 109 m
    nil,
    # 110 n
    nil,
    # 111 o
    nil,
    # 112 p
    :vi_paste_next,
    # 113 q
    nil,
    # 114 r
    :vi_replace_char,
    # 115 s
    nil,
    # 116 t
    :vi_to_next_char,
    # 117 u
    nil,
    # 118 v
    :vi_histedit,
    # 119 w
    :vi_next_word,
    # 120 x
    :ed_delete_next_char,
    # 121 y
    :vi_yank,
    # 122 z
    nil,
    # 123 {
    nil,
    # 124 |
    :vi_to_column,
    # 125 }
    nil,
    # 126 ~
    nil,
    # 127 ^?
    :em_delete_prev_char,
    # 128 M-^@
    nil,
    # 129 M-^A
    nil,
    # 130 M-^B
    nil,
    # 131 M-^C
    nil,
    # 132 M-^D
    nil,
    # 133 M-^E
    nil,
    # 134 M-^F
    nil,
    # 135 M-^G
    nil,
    # 136 M-^H
    nil,
    # 137 M-^I
    nil,
    # 138 M-^J
    nil,
    # 139 M-^K
    nil,
    # 140 M-^L
    nil,
    # 141 M-^M
    nil,
    # 142 M-^N
    nil,
    # 143 M-^O
    nil,
    # 144 M-^P
    nil,
    # 145 M-^Q
    nil,
    # 146 M-^R
    nil,
    # 147 M-^S
    nil,
    # 148 M-^T
    nil,
    # 149 M-^U
    nil,
    # 150 M-^V
    nil,
    # 151 M-^W
    nil,
    # 152 M-^X
    nil,
    # 153 M-^Y
    nil,
    # 154 M-^Z
    nil,
    # 155 M-^[
    nil,
    # 156 M-^\
    nil,
    # 157 M-^]
    nil,
    # 158 M-^^
    nil,
    # 159 M-^_
    nil,
    # 160 M-SPACE
    nil,
    # 161 M-!
    nil,
    # 162 M-"
    nil,
    # 163 M-#
    nil,
    # 164 M-$
    nil,
    # 165 M-%
    nil,
    # 166 M-&
    nil,
    # 167 M-'
    nil,
    # 168 M-(
    nil,
    # 169 M-)
    nil,
    # 170 M-*
    nil,
    # 171 M-+
    nil,
    # 172 M-,
    nil,
    # 173 M--
    nil,
    # 174 M-.
    nil,
    # 175 M-/
    nil,
    # 176 M-0
    nil,
    # 177 M-1
    nil,
    # 178 M-2
    nil,
    # 179 M-3
    nil,
    # 180 M-4
    nil,
    # 181 M-5
    nil,
    # 182 M-6
    nil,
    # 183 M-7
    nil,
    # 184 M-8
    nil,
    # 185 M-9
    nil,
    # 186 M-:
    nil,
    # 187 M-;
    nil,
    # 188 M-<
    nil,
    # 189 M-=
    nil,
    # 190 M->
    nil,
    # 191 M-?
    nil,
    # 192 M-@
    nil,
    # 193 M-A
    nil,
    # 194 M-B
    nil,
    # 195 M-C
    nil,
    # 196 M-D
    nil,
    # 197 M-E
    nil,
    # 198 M-F
    nil,
    # 199 M-G
    nil,
    # 200 M-H
    nil,
    # 201 M-I
    nil,
    # 202 M-J
    nil,
    # 203 M-K
    nil,
    # 204 M-L
    nil,
    # 205 M-M
    nil,
    # 206 M-N
    nil,
    # 207 M-O
    nil,
    # 208 M-P
    nil,
    # 209 M-Q
    nil,
    # 210 M-R
    nil,
    # 211 M-S
    nil,
    # 212 M-T
    nil,
    # 213 M-U
    nil,
    # 214 M-V
    nil,
    # 215 M-W
    nil,
    # 216 M-X
    nil,
    # 217 M-Y
    nil,
    # 218 M-Z
    nil,
    # 219 M-[
    nil,
    # 220 M-\
    nil,
    # 221 M-]
    nil,
    # 222 M-^
    nil,
    # 223 M-_
    nil,
    # 224 M-`
    nil,
    # 225 M-a
    nil,
    # 226 M-b
    nil,
    # 227 M-c
    nil,
    # 228 M-d
    nil,
    # 229 M-e
    nil,
    # 230 M-f
    nil,
    # 231 M-g
    nil,
    # 232 M-h
    nil,
    # 233 M-i
    nil,
    # 234 M-j
    nil,
    # 235 M-k
    nil,
    # 236 M-l
    nil,
    # 237 M-m
    nil,
    # 238 M-n
    nil,
    # 239 M-o
    nil,
    # 240 M-p
    nil,
    # 241 M-q
    nil,
    # 242 M-r
    nil,
    # 243 M-s
    nil,
    # 244 M-t
    nil,
    # 245 M-u
    nil,
    # 246 M-v
    nil,
    # 247 M-w
    nil,
    # 248 M-x
    nil,
    # 249 M-y
    nil,
    # 250 M-z
    nil,
    # 251 M-{
    nil,
    # 252 M-|
    nil,
    # 253 M-}
    nil,
    # 254 M-~
    nil,
    # 255 M-^?
    nil
    # EOF
  ]
end

