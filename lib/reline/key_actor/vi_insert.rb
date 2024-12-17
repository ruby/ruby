module Reline::KeyActor
  VI_INSERT_MAPPING = [
    #   0 ^@
    nil,
    #   1 ^A
    :ed_insert,
    #   2 ^B
    :ed_insert,
    #   3 ^C
    :ed_insert,
    #   4 ^D
    :vi_list_or_eof,
    #   5 ^E
    :ed_insert,
    #   6 ^F
    :ed_insert,
    #   7 ^G
    :ed_insert,
    #   8 ^H
    :vi_delete_prev_char,
    #   9 ^I
    :complete,
    #  10 ^J
    :ed_newline,
    #  11 ^K
    :ed_insert,
    #  12 ^L
    :ed_insert,
    #  13 ^M
    :ed_newline,
    #  14 ^N
    :menu_complete,
    #  15 ^O
    :ed_insert,
    #  16 ^P
    :menu_complete_backward,
    #  17 ^Q
    :ed_ignore,
    #  18 ^R
    :vi_search_prev,
    #  19 ^S
    :vi_search_next,
    #  20 ^T
    :ed_transpose_chars,
    #  21 ^U
    :vi_kill_line_prev,
    #  22 ^V
    :ed_quoted_insert,
    #  23 ^W
    :ed_delete_prev_word,
    #  24 ^X
    :ed_insert,
    #  25 ^Y
    :em_yank,
    #  26 ^Z
    :ed_insert,
    #  27 ^[
    :vi_command_mode,
    #  28 ^\
    :ed_ignore,
    #  29 ^]
    :ed_insert,
    #  30 ^^
    :ed_insert,
    #  31 ^_
    :ed_insert,
    #  32 SPACE
    :ed_insert,
    #  33 !
    :ed_insert,
    #  34 "
    :ed_insert,
    #  35 #
    :ed_insert,
    #  36 $
    :ed_insert,
    #  37 %
    :ed_insert,
    #  38 &
    :ed_insert,
    #  39 '
    :ed_insert,
    #  40 (
    :ed_insert,
    #  41 )
    :ed_insert,
    #  42 *
    :ed_insert,
    #  43 +
    :ed_insert,
    #  44 ,
    :ed_insert,
    #  45 -
    :ed_insert,
    #  46 .
    :ed_insert,
    #  47 /
    :ed_insert,
    #  48 0
    :ed_digit,
    #  49 1
    :ed_digit,
    #  50 2
    :ed_digit,
    #  51 3
    :ed_digit,
    #  52 4
    :ed_digit,
    #  53 5
    :ed_digit,
    #  54 6
    :ed_digit,
    #  55 7
    :ed_digit,
    #  56 8
    :ed_digit,
    #  57 9
    :ed_digit,
    #  58 :
    :ed_insert,
    #  59 ;
    :ed_insert,
    #  60 <
    :ed_insert,
    #  61 =
    :ed_insert,
    #  62 >
    :ed_insert,
    #  63 ?
    :ed_insert,
    #  64 @
    :ed_insert,
    #  65 A
    :ed_insert,
    #  66 B
    :ed_insert,
    #  67 C
    :ed_insert,
    #  68 D
    :ed_insert,
    #  69 E
    :ed_insert,
    #  70 F
    :ed_insert,
    #  71 G
    :ed_insert,
    #  72 H
    :ed_insert,
    #  73 I
    :ed_insert,
    #  74 J
    :ed_insert,
    #  75 K
    :ed_insert,
    #  76 L
    :ed_insert,
    #  77 M
    :ed_insert,
    #  78 N
    :ed_insert,
    #  79 O
    :ed_insert,
    #  80 P
    :ed_insert,
    #  81 Q
    :ed_insert,
    #  82 R
    :ed_insert,
    #  83 S
    :ed_insert,
    #  84 T
    :ed_insert,
    #  85 U
    :ed_insert,
    #  86 V
    :ed_insert,
    #  87 W
    :ed_insert,
    #  88 X
    :ed_insert,
    #  89 Y
    :ed_insert,
    #  90 Z
    :ed_insert,
    #  91 [
    :ed_insert,
    #  92 \
    :ed_insert,
    #  93 ]
    :ed_insert,
    #  94 ^
    :ed_insert,
    #  95 _
    :ed_insert,
    #  96 `
    :ed_insert,
    #  97 a
    :ed_insert,
    #  98 b
    :ed_insert,
    #  99 c
    :ed_insert,
    # 100 d
    :ed_insert,
    # 101 e
    :ed_insert,
    # 102 f
    :ed_insert,
    # 103 g
    :ed_insert,
    # 104 h
    :ed_insert,
    # 105 i
    :ed_insert,
    # 106 j
    :ed_insert,
    # 107 k
    :ed_insert,
    # 108 l
    :ed_insert,
    # 109 m
    :ed_insert,
    # 110 n
    :ed_insert,
    # 111 o
    :ed_insert,
    # 112 p
    :ed_insert,
    # 113 q
    :ed_insert,
    # 114 r
    :ed_insert,
    # 115 s
    :ed_insert,
    # 116 t
    :ed_insert,
    # 117 u
    :ed_insert,
    # 118 v
    :ed_insert,
    # 119 w
    :ed_insert,
    # 120 x
    :ed_insert,
    # 121 y
    :ed_insert,
    # 122 z
    :ed_insert,
    # 123 {
    :ed_insert,
    # 124 |
    :ed_insert,
    # 125 }
    :ed_insert,
    # 126 ~
    :ed_insert,
    # 127 ^?
    :vi_delete_prev_char,
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
    :key_newline,
    # 139 M-^K
    nil,
    # 140 M-^L
    nil,
    # 141 M-^M
    :key_newline,
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
