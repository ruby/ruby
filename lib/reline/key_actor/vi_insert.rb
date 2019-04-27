class Reline::KeyActor::ViInsert < Reline::KeyActor::Base
  MAPPING = [
    #   0 ^@
    :ed_unassigned,
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
    :ed_insert,
    #  10 ^J
    :ed_newline,
    #  11 ^K
    :ed_insert,
    #  12 ^L
    :ed_insert,
    #  13 ^M
    :ed_newline,
    #  14 ^N
    :ed_insert,
    #  15 ^O
    :ed_insert,
    #  16 ^P
    :ed_insert,
    #  17 ^Q
    :ed_ignore,
    #  18 ^R
    :ed_insert,
    #  19 ^S
    :ed_ignore,
    #  20 ^T
    :ed_insert,
    #  21 ^U
    :vi_kill_line_prev,
    #  22 ^V
    :ed_quoted_insert,
    #  23 ^W
    :ed_delete_prev_word,
    #  24 ^X
    :ed_insert,
    #  25 ^Y
    :ed_insert,
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
    :ed_insert,
    #  49 1
    :ed_insert,
    #  50 2
    :ed_insert,
    #  51 3
    :ed_insert,
    #  52 4
    :ed_insert,
    #  53 5
    :ed_insert,
    #  54 6
    :ed_insert,
    #  55 7
    :ed_insert,
    #  56 8
    :ed_insert,
    #  57 9
    :ed_insert,
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
    :ed_insert,
    # 129 M-^A
    :ed_insert,
    # 130 M-^B
    :ed_insert,
    # 131 M-^C
    :ed_insert,
    # 132 M-^D
    :ed_insert,
    # 133 M-^E
    :ed_insert,
    # 134 M-^F
    :ed_insert,
    # 135 M-^G
    :ed_insert,
    # 136 M-^H
    :ed_insert,
    # 137 M-^I
    :ed_insert,
    # 138 M-^J
    :ed_insert,
    # 139 M-^K
    :ed_insert,
    # 140 M-^L
    :ed_insert,
    # 141 M-^M
    :ed_insert,
    # 142 M-^N
    :ed_insert,
    # 143 M-^O
    :ed_insert,
    # 144 M-^P
    :ed_insert,
    # 145 M-^Q
    :ed_insert,
    # 146 M-^R
    :ed_insert,
    # 147 M-^S
    :ed_insert,
    # 148 M-^T
    :ed_insert,
    # 149 M-^U
    :ed_insert,
    # 150 M-^V
    :ed_insert,
    # 151 M-^W
    :ed_insert,
    # 152 M-^X
    :ed_insert,
    # 153 M-^Y
    :ed_insert,
    # 154 M-^Z
    :ed_insert,
    # 155 M-^[
    :ed_insert,
    # 156 M-^\
    :ed_insert,
    # 157 M-^]
    :ed_insert,
    # 158 M-^^
    :ed_insert,
    # 159 M-^_
    :ed_insert,
    # 160 M-SPACE
    :ed_insert,
    # 161 M-!
    :ed_insert,
    # 162 M-"
    :ed_insert,
    # 163 M-#
    :ed_insert,
    # 164 M-$
    :ed_insert,
    # 165 M-%
    :ed_insert,
    # 166 M-&
    :ed_insert,
    # 167 M-'
    :ed_insert,
    # 168 M-(
    :ed_insert,
    # 169 M-)
    :ed_insert,
    # 170 M-*
    :ed_insert,
    # 171 M-+
    :ed_insert,
    # 172 M-,
    :ed_insert,
    # 173 M--
    :ed_insert,
    # 174 M-.
    :ed_insert,
    # 175 M-/
    :ed_insert,
    # 176 M-0
    :ed_insert,
    # 177 M-1
    :ed_insert,
    # 178 M-2
    :ed_insert,
    # 179 M-3
    :ed_insert,
    # 180 M-4
    :ed_insert,
    # 181 M-5
    :ed_insert,
    # 182 M-6
    :ed_insert,
    # 183 M-7
    :ed_insert,
    # 184 M-8
    :ed_insert,
    # 185 M-9
    :ed_insert,
    # 186 M-:
    :ed_insert,
    # 187 M-;
    :ed_insert,
    # 188 M-<
    :ed_insert,
    # 189 M-=
    :ed_insert,
    # 190 M->
    :ed_insert,
    # 191 M-?
    :ed_insert,
    # 192 M-@
    :ed_insert,
    # 193 M-A
    :ed_insert,
    # 194 M-B
    :ed_insert,
    # 195 M-C
    :ed_insert,
    # 196 M-D
    :ed_insert,
    # 197 M-E
    :ed_insert,
    # 198 M-F
    :ed_insert,
    # 199 M-G
    :ed_insert,
    # 200 M-H
    :ed_insert,
    # 201 M-I
    :ed_insert,
    # 202 M-J
    :ed_insert,
    # 203 M-K
    :ed_insert,
    # 204 M-L
    :ed_insert,
    # 205 M-M
    :ed_insert,
    # 206 M-N
    :ed_insert,
    # 207 M-O
    :ed_insert,
    # 208 M-P
    :ed_insert,
    # 209 M-Q
    :ed_insert,
    # 210 M-R
    :ed_insert,
    # 211 M-S
    :ed_insert,
    # 212 M-T
    :ed_insert,
    # 213 M-U
    :ed_insert,
    # 214 M-V
    :ed_insert,
    # 215 M-W
    :ed_insert,
    # 216 M-X
    :ed_insert,
    # 217 M-Y
    :ed_insert,
    # 218 M-Z
    :ed_insert,
    # 219 M-[
    :ed_insert,
    # 220 M-\
    :ed_insert,
    # 221 M-]
    :ed_insert,
    # 222 M-^
    :ed_insert,
    # 223 M-_
    :ed_insert,
    # 223 M-`
    :ed_insert,
    # 224 M-a
    :ed_insert,
    # 225 M-b
    :ed_insert,
    # 226 M-c
    :ed_insert,
    # 227 M-d
    :ed_insert,
    # 228 M-e
    :ed_insert,
    # 229 M-f
    :ed_insert,
    # 230 M-g
    :ed_insert,
    # 231 M-h
    :ed_insert,
    # 232 M-i
    :ed_insert,
    # 233 M-j
    :ed_insert,
    # 234 M-k
    :ed_insert,
    # 235 M-l
    :ed_insert,
    # 236 M-m
    :ed_insert,
    # 237 M-n
    :ed_insert,
    # 238 M-o
    :ed_insert,
    # 239 M-p
    :ed_insert,
    # 240 M-q
    :ed_insert,
    # 241 M-r
    :ed_insert,
    # 242 M-s
    :ed_insert,
    # 243 M-t
    :ed_insert,
    # 244 M-u
    :ed_insert,
    # 245 M-v
    :ed_insert,
    # 246 M-w
    :ed_insert,
    # 247 M-x
    :ed_insert,
    # 248 M-y
    :ed_insert,
    # 249 M-z
    :ed_insert,
    # 250 M-{
    :ed_insert,
    # 251 M-|
    :ed_insert,
    # 252 M-}
    :ed_insert,
    # 253 M-~
    :ed_insert,
    # 254	M-^?
    :ed_insert
    # 255
    # EOF
  ]
end
