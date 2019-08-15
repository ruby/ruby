class Reline::Unicode::EastAsianWidth
  # This is based on EastAsianWidth.txt
  # http://www.unicode.org/Public/12.1.0/ucd/EastAsianWidth.txt

  # Fullwidth
  TYPE_F = /^(
    \u{3000} |
    [\u{FF01}-\u{FF60}] |
    [\u{FFE0}-\u{FFE6}]
  )/x

  # Halfwidth
  TYPE_H = /^(
    \u{20A9} |
    [\u{FF61}-\u{FFBE}] |
    [\u{FFC2}-\u{FFC7}] |
    [\u{FFCA}-\u{FFCF}] |
    [\u{FFD2}-\u{FFD7}] |
    [\u{FFDA}-\u{FFDC}] |
    [\u{FFE8}-\u{FFEE}]
  )/x

  # Wide
  TYPE_W = /^(
    [\u{1100}-\u{115F}] |
    [\u{231A}-\u{231B}] |
    [\u{2329}-\u{232A}] |
    [\u{23E9}-\u{23EC}] |
    \u{23F0} |
    \u{23F3} |
    [\u{25FD}-\u{25FE}] |
    [\u{2614}-\u{2615}] |
    [\u{2648}-\u{2653}] |
    \u{267F} |
    \u{2693} |
    \u{26A1} |
    [\u{26AA}-\u{26AB}] |
    [\u{26BD}-\u{26BE}] |
    [\u{26C4}-\u{26C5}] |
    \u{26CE} |
    \u{26D4} |
    \u{26EA} |
    [\u{26F2}-\u{26F3}] |
    \u{26F5} |
    \u{26FA} |
    \u{26FD} |
    \u{2705} |
    [\u{270A}-\u{270B}] |
    \u{2728} |
    \u{274C} |
    \u{274E} |
    [\u{2753}-\u{2755}] |
    \u{2757} |
    [\u{2795}-\u{2797}] |
    \u{27B0} |
    \u{27BF} |
    [\u{2B1B}-\u{2B1C}] |
    \u{2B50} |
    \u{2B55} |
    [\u{2E80}-\u{2E99}] |
    [\u{2E9B}-\u{2EF3}] |
    [\u{2F00}-\u{2FD5}] |
    [\u{2FF0}-\u{2FFB}] |
    [\u{3001}-\u{303E}] |
    [\u{3041}-\u{3096}] |
    [\u{3099}-\u{30FF}] |
    [\u{3105}-\u{312F}] |
    [\u{3131}-\u{318E}] |
    [\u{3190}-\u{31BA}] |
    [\u{31C0}-\u{31E3}] |
    [\u{31F0}-\u{321E}] |
    [\u{3220}-\u{3247}] |
    [\u{3250}-\u{4DBF}] |
    [\u{4E00}-\u{A48C}] |
    [\u{A490}-\u{A4C6}] |
    [\u{A960}-\u{A97C}] |
    [\u{AC00}-\u{D7A3}] |
    [\u{F900}-\u{FAFF}] |
    [\u{FE10}-\u{FE19}] |
    [\u{FE30}-\u{FE52}] |
    [\u{FE54}-\u{FE66}] |
    [\u{FE68}-\u{FE6B}] |
    [\u{16FE0}-\u{16FE3}] |
    [\u{17000}-\u{187F7}] |
    [\u{18800}-\u{18AF2}] |
    [\u{1B000}-\u{1B11E}] |
    [\u{1B150}-\u{1B152}] |
    [\u{1B164}-\u{1B167}] |
    [\u{1B170}-\u{1B2FB}] |
    \u{1F004} |
    \u{1F0CF} |
    \u{1F18E} |
    [\u{1F191}-\u{1F19A}] |
    [\u{1F200}-\u{1F202}] |
    [\u{1F210}-\u{1F23B}] |
    [\u{1F240}-\u{1F248}] |
    [\u{1F250}-\u{1F251}] |
    [\u{1F260}-\u{1F265}] |
    [\u{1F300}-\u{1F320}] |
    [\u{1F32D}-\u{1F335}] |
    [\u{1F337}-\u{1F37C}] |
    [\u{1F37E}-\u{1F393}] |
    [\u{1F3A0}-\u{1F3CA}] |
    [\u{1F3CF}-\u{1F3D3}] |
    [\u{1F3E0}-\u{1F3F0}] |
    \u{1F3F4} |
    [\u{1F3F8}-\u{1F43E}] |
    \u{1F440} |
    [\u{1F442}-\u{1F4FC}] |
    [\u{1F4FF}-\u{1F53D}] |
    [\u{1F54B}-\u{1F54E}] |
    [\u{1F550}-\u{1F567}] |
    \u{1F57A} |
    [\u{1F595}-\u{1F596}] |
    \u{1F5A4} |
    [\u{1F5FB}-\u{1F64F}] |
    [\u{1F680}-\u{1F6C5}] |
    \u{1F6CC} |
    [\u{1F6D0}-\u{1F6D2}] |
    \u{1F6D5} |
    [\u{1F6EB}-\u{1F6EC}] |
    [\u{1F6F4}-\u{1F6FA}] |
    [\u{1F7E0}-\u{1F7EB}] |
    [\u{1F90D}-\u{1F971}] |
    [\u{1F973}-\u{1F976}] |
    [\u{1F97A}-\u{1F9A2}] |
    [\u{1F9A5}-\u{1F9AA}] |
    [\u{1F9AE}-\u{1F9CA}] |
    [\u{1F9CD}-\u{1F9FF}] |
    [\u{1FA70}-\u{1FA73}] |
    [\u{1FA78}-\u{1FA7A}] |
    [\u{1FA80}-\u{1FA82}] |
    [\u{1FA90}-\u{1FA95}] |
    [\u{20000}-\u{2FFFD}] |
    [\u{30000}-\u{3FFFD}]
  )/x

  # Narrow
  TYPE_NA = /^(
    [\u{0020}-\u{007E}] |
    [\u{00A2}-\u{00A3}] |
    [\u{00A5}-\u{00A6}] |
    \u{00AC} |
    \u{00AF} |
    [\u{27E6}-\u{27ED}] |
    [\u{2985}-\u{2986}]
  )/x

  # Ambiguous
  TYPE_A = /^(
    \u{00A1} |
    \u{00A4} |
    [\u{00A7}-\u{00A8}] |
    \u{00AA} |
    [\u{00AD}-\u{00AE}] |
    [\u{00B0}-\u{00B4}] |
    [\u{00B6}-\u{00BA}] |
    [\u{00BC}-\u{00BF}] |
    \u{00C6} |
    \u{00D0} |
    [\u{00D7}-\u{00D8}] |
    [\u{00DE}-\u{00E1}] |
    \u{00E6} |
    [\u{00E8}-\u{00EA}] |
    [\u{00EC}-\u{00ED}] |
    \u{00F0} |
    [\u{00F2}-\u{00F3}] |
    [\u{00F7}-\u{00FA}] |
    \u{00FC} |
    \u{00FE} |
    \u{0101} |
    \u{0111} |
    \u{0113} |
    \u{011B} |
    [\u{0126}-\u{0127}] |
    \u{012B} |
    [\u{0131}-\u{0133}] |
    \u{0138} |
    [\u{013F}-\u{0142}] |
    \u{0144} |
    [\u{0148}-\u{014B}] |
    \u{014D} |
    [\u{0152}-\u{0153}] |
    [\u{0166}-\u{0167}] |
    \u{016B} |
    \u{01CE} |
    \u{01D0} |
    \u{01D2} |
    \u{01D4} |
    \u{01D6} |
    \u{01D8} |
    \u{01DA} |
    \u{01DC} |
    \u{0251} |
    \u{0261} |
    \u{02C4} |
    \u{02C7} |
    [\u{02C9}-\u{02CB}] |
    \u{02CD} |
    \u{02D0} |
    [\u{02D8}-\u{02DB}] |
    \u{02DD} |
    \u{02DF} |
    [\u{0300}-\u{036F}] |
    [\u{0391}-\u{03A1}] |
    [\u{03A3}-\u{03A9}] |
    [\u{03B1}-\u{03C1}] |
    [\u{03C3}-\u{03C9}] |
    \u{0401} |
    [\u{0410}-\u{044F}] |
    \u{0451} |
    \u{2010} |
    [\u{2013}-\u{2016}] |
    [\u{2018}-\u{2019}] |
    [\u{201C}-\u{201D}] |
    [\u{2020}-\u{2022}] |
    [\u{2024}-\u{2027}] |
    \u{2030} |
    [\u{2032}-\u{2033}] |
    \u{2035} |
    \u{203B} |
    \u{203E} |
    \u{2074} |
    \u{207F} |
    [\u{2081}-\u{2084}] |
    \u{20AC} |
    \u{2103} |
    \u{2105} |
    \u{2109} |
    \u{2113} |
    \u{2116} |
    [\u{2121}-\u{2122}] |
    \u{2126} |
    \u{212B} |
    [\u{2153}-\u{2154}] |
    [\u{215B}-\u{215E}] |
    [\u{2160}-\u{216B}] |
    [\u{2170}-\u{2179}] |
    \u{2189} |
    [\u{2190}-\u{2199}] |
    [\u{21B8}-\u{21B9}] |
    \u{21D2} |
    \u{21D4} |
    \u{21E7} |
    \u{2200} |
    [\u{2202}-\u{2203}] |
    [\u{2207}-\u{2208}] |
    \u{220B} |
    \u{220F} |
    \u{2211} |
    \u{2215} |
    \u{221A} |
    [\u{221D}-\u{2220}] |
    \u{2223} |
    \u{2225} |
    [\u{2227}-\u{222C}] |
    \u{222E} |
    [\u{2234}-\u{2237}] |
    [\u{223C}-\u{223D}] |
    \u{2248} |
    \u{224C} |
    \u{2252} |
    [\u{2260}-\u{2261}] |
    [\u{2264}-\u{2267}] |
    [\u{226A}-\u{226B}] |
    [\u{226E}-\u{226F}] |
    [\u{2282}-\u{2283}] |
    [\u{2286}-\u{2287}] |
    \u{2295} |
    \u{2299} |
    \u{22A5} |
    \u{22BF} |
    \u{2312} |
    [\u{2460}-\u{24E9}] |
    [\u{24EB}-\u{254B}] |
    [\u{2550}-\u{2573}] |
    [\u{2580}-\u{258F}] |
    [\u{2592}-\u{2595}] |
    [\u{25A0}-\u{25A1}] |
    [\u{25A3}-\u{25A9}] |
    [\u{25B2}-\u{25B3}] |
    [\u{25B6}-\u{25B7}] |
    [\u{25BC}-\u{25BD}] |
    [\u{25C0}-\u{25C1}] |
    [\u{25C6}-\u{25C8}] |
    \u{25CB} |
    [\u{25CE}-\u{25D1}] |
    [\u{25E2}-\u{25E5}] |
    \u{25EF} |
    [\u{2605}-\u{2606}] |
    \u{2609} |
    [\u{260E}-\u{260F}] |
    \u{261C} |
    \u{261E} |
    \u{2640} |
    \u{2642} |
    [\u{2660}-\u{2661}] |
    [\u{2663}-\u{2665}] |
    [\u{2667}-\u{266A}] |
    [\u{266C}-\u{266D}] |
    \u{266F} |
    [\u{269E}-\u{269F}] |
    \u{26BF} |
    [\u{26C6}-\u{26CD}] |
    [\u{26CF}-\u{26D3}] |
    [\u{26D5}-\u{26E1}] |
    \u{26E3} |
    [\u{26E8}-\u{26E9}] |
    [\u{26EB}-\u{26F1}] |
    \u{26F4} |
    [\u{26F6}-\u{26F9}] |
    [\u{26FB}-\u{26FC}] |
    [\u{26FE}-\u{26FF}] |
    \u{273D} |
    [\u{2776}-\u{277F}] |
    [\u{2B56}-\u{2B59}] |
    [\u{3248}-\u{324F}] |
    [\u{E000}-\u{F8FF}] |
    [\u{FE00}-\u{FE0F}] |
    \u{FFFD} |
    [\u{1F100}-\u{1F10A}] |
    [\u{1F110}-\u{1F12D}] |
    [\u{1F130}-\u{1F169}] |
    [\u{1F170}-\u{1F18D}] |
    [\u{1F18F}-\u{1F190}] |
    [\u{1F19B}-\u{1F1AC}] |
    [\u{E0100}-\u{E01EF}] |
    [\u{F0000}-\u{FFFFD}] |
    [\u{100000}-\u{10FFFD}]
  )/x

  # Neutral
  TYPE_N = /^(
    [\u{0000}-\u{001F}] |
    [\u{007F}-\u{00A0}] |
    \u{00A9} |
    \u{00AB} |
    \u{00B5} |
    \u{00BB} |
    [\u{00C0}-\u{00C5}] |
    [\u{00C7}-\u{00CF}] |
    [\u{00D1}-\u{00D6}] |
    [\u{00D9}-\u{00DD}] |
    [\u{00E2}-\u{00E5}] |
    \u{00E7} |
    \u{00EB} |
    [\u{00EE}-\u{00EF}] |
    \u{00F1} |
    [\u{00F4}-\u{00F6}] |
    \u{00FB} |
    \u{00FD} |
    [\u{00FF}-\u{0100}] |
    [\u{0102}-\u{0110}] |
    \u{0112} |
    [\u{0114}-\u{011A}] |
    [\u{011C}-\u{0125}] |
    [\u{0128}-\u{012A}] |
    [\u{012C}-\u{0130}] |
    [\u{0134}-\u{0137}] |
    [\u{0139}-\u{013E}] |
    \u{0143} |
    [\u{0145}-\u{0147}] |
    \u{014C} |
    [\u{014E}-\u{0151}] |
    [\u{0154}-\u{0165}] |
    [\u{0168}-\u{016A}] |
    [\u{016C}-\u{01CD}] |
    \u{01CF} |
    \u{01D1} |
    \u{01D3} |
    \u{01D5} |
    \u{01D7} |
    \u{01D9} |
    \u{01DB} |
    [\u{01DD}-\u{0250}] |
    [\u{0252}-\u{0260}] |
    [\u{0262}-\u{02C3}] |
    [\u{02C5}-\u{02C6}] |
    \u{02C8} |
    \u{02CC} |
    [\u{02CE}-\u{02CF}] |
    [\u{02D1}-\u{02D7}] |
    \u{02DC} |
    \u{02DE} |
    [\u{02E0}-\u{02FF}] |
    [\u{0370}-\u{0377}] |
    [\u{037A}-\u{037F}] |
    [\u{0384}-\u{038A}] |
    \u{038C} |
    [\u{038E}-\u{0390}] |
    [\u{03AA}-\u{03B0}] |
    \u{03C2} |
    [\u{03CA}-\u{0400}] |
    [\u{0402}-\u{040F}] |
    \u{0450} |
    [\u{0452}-\u{052F}] |
    [\u{0531}-\u{0556}] |
    [\u{0559}-\u{058A}] |
    [\u{058D}-\u{058F}] |
    [\u{0591}-\u{05C7}] |
    [\u{05D0}-\u{05EA}] |
    [\u{05EF}-\u{05F4}] |
    [\u{0600}-\u{061C}] |
    [\u{061E}-\u{070D}] |
    [\u{070F}-\u{074A}] |
    [\u{074D}-\u{07B1}] |
    [\u{07C0}-\u{07FA}] |
    [\u{07FD}-\u{082D}] |
    [\u{0830}-\u{083E}] |
    [\u{0840}-\u{085B}] |
    \u{085E} |
    [\u{0860}-\u{086A}] |
    [\u{08A0}-\u{08B4}] |
    [\u{08B6}-\u{08BD}] |
    [\u{08D3}-\u{0983}] |
    [\u{0985}-\u{098C}] |
    [\u{098F}-\u{0990}] |
    [\u{0993}-\u{09A8}] |
    [\u{09AA}-\u{09B0}] |
    \u{09B2} |
    [\u{09B6}-\u{09B9}] |
    [\u{09BC}-\u{09C4}] |
    [\u{09C7}-\u{09C8}] |
    [\u{09CB}-\u{09CE}] |
    \u{09D7} |
    [\u{09DC}-\u{09DD}] |
    [\u{09DF}-\u{09E3}] |
    [\u{09E6}-\u{09FE}] |
    [\u{0A01}-\u{0A03}] |
    [\u{0A05}-\u{0A0A}] |
    [\u{0A0F}-\u{0A10}] |
    [\u{0A13}-\u{0A28}] |
    [\u{0A2A}-\u{0A30}] |
    [\u{0A32}-\u{0A33}] |
    [\u{0A35}-\u{0A36}] |
    [\u{0A38}-\u{0A39}] |
    \u{0A3C} |
    [\u{0A3E}-\u{0A42}] |
    [\u{0A47}-\u{0A48}] |
    [\u{0A4B}-\u{0A4D}] |
    \u{0A51} |
    [\u{0A59}-\u{0A5C}] |
    \u{0A5E} |
    [\u{0A66}-\u{0A76}] |
    [\u{0A81}-\u{0A83}] |
    [\u{0A85}-\u{0A8D}] |
    [\u{0A8F}-\u{0A91}] |
    [\u{0A93}-\u{0AA8}] |
    [\u{0AAA}-\u{0AB0}] |
    [\u{0AB2}-\u{0AB3}] |
    [\u{0AB5}-\u{0AB9}] |
    [\u{0ABC}-\u{0AC5}] |
    [\u{0AC7}-\u{0AC9}] |
    [\u{0ACB}-\u{0ACD}] |
    \u{0AD0} |
    [\u{0AE0}-\u{0AE3}] |
    [\u{0AE6}-\u{0AF1}] |
    [\u{0AF9}-\u{0AFF}] |
    [\u{0B01}-\u{0B03}] |
    [\u{0B05}-\u{0B0C}] |
    [\u{0B0F}-\u{0B10}] |
    [\u{0B13}-\u{0B28}] |
    [\u{0B2A}-\u{0B30}] |
    [\u{0B32}-\u{0B33}] |
    [\u{0B35}-\u{0B39}] |
    [\u{0B3C}-\u{0B44}] |
    [\u{0B47}-\u{0B48}] |
    [\u{0B4B}-\u{0B4D}] |
    [\u{0B56}-\u{0B57}] |
    [\u{0B5C}-\u{0B5D}] |
    [\u{0B5F}-\u{0B63}] |
    [\u{0B66}-\u{0B77}] |
    [\u{0B82}-\u{0B83}] |
    [\u{0B85}-\u{0B8A}] |
    [\u{0B8E}-\u{0B90}] |
    [\u{0B92}-\u{0B95}] |
    [\u{0B99}-\u{0B9A}] |
    \u{0B9C} |
    [\u{0B9E}-\u{0B9F}] |
    [\u{0BA3}-\u{0BA4}] |
    [\u{0BA8}-\u{0BAA}] |
    [\u{0BAE}-\u{0BB9}] |
    [\u{0BBE}-\u{0BC2}] |
    [\u{0BC6}-\u{0BC8}] |
    [\u{0BCA}-\u{0BCD}] |
    \u{0BD0} |
    \u{0BD7} |
    [\u{0BE6}-\u{0BFA}] |
    [\u{0C00}-\u{0C0C}] |
    [\u{0C0E}-\u{0C10}] |
    [\u{0C12}-\u{0C28}] |
    [\u{0C2A}-\u{0C39}] |
    [\u{0C3D}-\u{0C44}] |
    [\u{0C46}-\u{0C48}] |
    [\u{0C4A}-\u{0C4D}] |
    [\u{0C55}-\u{0C56}] |
    [\u{0C58}-\u{0C5A}] |
    [\u{0C60}-\u{0C63}] |
    [\u{0C66}-\u{0C6F}] |
    [\u{0C77}-\u{0C8C}] |
    [\u{0C8E}-\u{0C90}] |
    [\u{0C92}-\u{0CA8}] |
    [\u{0CAA}-\u{0CB3}] |
    [\u{0CB5}-\u{0CB9}] |
    [\u{0CBC}-\u{0CC4}] |
    [\u{0CC6}-\u{0CC8}] |
    [\u{0CCA}-\u{0CCD}] |
    [\u{0CD5}-\u{0CD6}] |
    \u{0CDE} |
    [\u{0CE0}-\u{0CE3}] |
    [\u{0CE6}-\u{0CEF}] |
    [\u{0CF1}-\u{0CF2}] |
    [\u{0D00}-\u{0D03}] |
    [\u{0D05}-\u{0D0C}] |
    [\u{0D0E}-\u{0D10}] |
    [\u{0D12}-\u{0D44}] |
    [\u{0D46}-\u{0D48}] |
    [\u{0D4A}-\u{0D4F}] |
    [\u{0D54}-\u{0D63}] |
    [\u{0D66}-\u{0D7F}] |
    [\u{0D82}-\u{0D83}] |
    [\u{0D85}-\u{0D96}] |
    [\u{0D9A}-\u{0DB1}] |
    [\u{0DB3}-\u{0DBB}] |
    \u{0DBD} |
    [\u{0DC0}-\u{0DC6}] |
    \u{0DCA} |
    [\u{0DCF}-\u{0DD4}] |
    \u{0DD6} |
    [\u{0DD8}-\u{0DDF}] |
    [\u{0DE6}-\u{0DEF}] |
    [\u{0DF2}-\u{0DF4}] |
    [\u{0E01}-\u{0E3A}] |
    [\u{0E3F}-\u{0E5B}] |
    [\u{0E81}-\u{0E82}] |
    \u{0E84} |
    [\u{0E86}-\u{0E8A}] |
    [\u{0E8C}-\u{0EA3}] |
    \u{0EA5} |
    [\u{0EA7}-\u{0EBD}] |
    [\u{0EC0}-\u{0EC4}] |
    \u{0EC6} |
    [\u{0EC8}-\u{0ECD}] |
    [\u{0ED0}-\u{0ED9}] |
    [\u{0EDC}-\u{0EDF}] |
    [\u{0F00}-\u{0F47}] |
    [\u{0F49}-\u{0F6C}] |
    [\u{0F71}-\u{0F97}] |
    [\u{0F99}-\u{0FBC}] |
    [\u{0FBE}-\u{0FCC}] |
    [\u{0FCE}-\u{0FDA}] |
    [\u{1000}-\u{10C5}] |
    \u{10C7} |
    \u{10CD} |
    [\u{10D0}-\u{10FF}] |
    [\u{1160}-\u{1248}] |
    [\u{124A}-\u{124D}] |
    [\u{1250}-\u{1256}] |
    \u{1258} |
    [\u{125A}-\u{125D}] |
    [\u{1260}-\u{1288}] |
    [\u{128A}-\u{128D}] |
    [\u{1290}-\u{12B0}] |
    [\u{12B2}-\u{12B5}] |
    [\u{12B8}-\u{12BE}] |
    \u{12C0} |
    [\u{12C2}-\u{12C5}] |
    [\u{12C8}-\u{12D6}] |
    [\u{12D8}-\u{1310}] |
    [\u{1312}-\u{1315}] |
    [\u{1318}-\u{135A}] |
    [\u{135D}-\u{137C}] |
    [\u{1380}-\u{1399}] |
    [\u{13A0}-\u{13F5}] |
    [\u{13F8}-\u{13FD}] |
    [\u{1400}-\u{169C}] |
    [\u{16A0}-\u{16F8}] |
    [\u{1700}-\u{170C}] |
    [\u{170E}-\u{1714}] |
    [\u{1720}-\u{1736}] |
    [\u{1740}-\u{1753}] |
    [\u{1760}-\u{176C}] |
    [\u{176E}-\u{1770}] |
    [\u{1772}-\u{1773}] |
    [\u{1780}-\u{17DD}] |
    [\u{17E0}-\u{17E9}] |
    [\u{17F0}-\u{17F9}] |
    [\u{1800}-\u{180E}] |
    [\u{1810}-\u{1819}] |
    [\u{1820}-\u{1878}] |
    [\u{1880}-\u{18AA}] |
    [\u{18B0}-\u{18F5}] |
    [\u{1900}-\u{191E}] |
    [\u{1920}-\u{192B}] |
    [\u{1930}-\u{193B}] |
    \u{1940} |
    [\u{1944}-\u{196D}] |
    [\u{1970}-\u{1974}] |
    [\u{1980}-\u{19AB}] |
    [\u{19B0}-\u{19C9}] |
    [\u{19D0}-\u{19DA}] |
    [\u{19DE}-\u{1A1B}] |
    [\u{1A1E}-\u{1A5E}] |
    [\u{1A60}-\u{1A7C}] |
    [\u{1A7F}-\u{1A89}] |
    [\u{1A90}-\u{1A99}] |
    [\u{1AA0}-\u{1AAD}] |
    [\u{1AB0}-\u{1ABE}] |
    [\u{1B00}-\u{1B4B}] |
    [\u{1B50}-\u{1B7C}] |
    [\u{1B80}-\u{1BF3}] |
    [\u{1BFC}-\u{1C37}] |
    [\u{1C3B}-\u{1C49}] |
    [\u{1C4D}-\u{1C88}] |
    [\u{1C90}-\u{1CBA}] |
    [\u{1CBD}-\u{1CC7}] |
    [\u{1CD0}-\u{1CFA}] |
    [\u{1D00}-\u{1DF9}] |
    [\u{1DFB}-\u{1F15}] |
    [\u{1F18}-\u{1F1D}] |
    [\u{1F20}-\u{1F45}] |
    [\u{1F48}-\u{1F4D}] |
    [\u{1F50}-\u{1F57}] |
    \u{1F59} |
    \u{1F5B} |
    \u{1F5D} |
    [\u{1F5F}-\u{1F7D}] |
    [\u{1F80}-\u{1FB4}] |
    [\u{1FB6}-\u{1FC4}] |
    [\u{1FC6}-\u{1FD3}] |
    [\u{1FD6}-\u{1FDB}] |
    [\u{1FDD}-\u{1FEF}] |
    [\u{1FF2}-\u{1FF4}] |
    [\u{1FF6}-\u{1FFE}] |
    [\u{2000}-\u{200F}] |
    [\u{2011}-\u{2012}] |
    \u{2017} |
    [\u{201A}-\u{201B}] |
    [\u{201E}-\u{201F}] |
    \u{2023} |
    [\u{2028}-\u{202F}] |
    \u{2031} |
    \u{2034} |
    [\u{2036}-\u{203A}] |
    [\u{203C}-\u{203D}] |
    [\u{203F}-\u{2064}] |
    [\u{2066}-\u{2071}] |
    [\u{2075}-\u{207E}] |
    \u{2080} |
    [\u{2085}-\u{208E}] |
    [\u{2090}-\u{209C}] |
    [\u{20A0}-\u{20A8}] |
    [\u{20AA}-\u{20AB}] |
    [\u{20AD}-\u{20BF}] |
    [\u{20D0}-\u{20F0}] |
    [\u{2100}-\u{2102}] |
    \u{2104} |
    [\u{2106}-\u{2108}] |
    [\u{210A}-\u{2112}] |
    [\u{2114}-\u{2115}] |
    [\u{2117}-\u{2120}] |
    [\u{2123}-\u{2125}] |
    [\u{2127}-\u{212A}] |
    [\u{212C}-\u{2152}] |
    [\u{2155}-\u{215A}] |
    \u{215F} |
    [\u{216C}-\u{216F}] |
    [\u{217A}-\u{2188}] |
    [\u{218A}-\u{218B}] |
    [\u{219A}-\u{21B7}] |
    [\u{21BA}-\u{21D1}] |
    \u{21D3} |
    [\u{21D5}-\u{21E6}] |
    [\u{21E8}-\u{21FF}] |
    \u{2201} |
    [\u{2204}-\u{2206}] |
    [\u{2209}-\u{220A}] |
    [\u{220C}-\u{220E}] |
    \u{2210} |
    [\u{2212}-\u{2214}] |
    [\u{2216}-\u{2219}] |
    [\u{221B}-\u{221C}] |
    [\u{2221}-\u{2222}] |
    \u{2224} |
    \u{2226} |
    \u{222D} |
    [\u{222F}-\u{2233}] |
    [\u{2238}-\u{223B}] |
    [\u{223E}-\u{2247}] |
    [\u{2249}-\u{224B}] |
    [\u{224D}-\u{2251}] |
    [\u{2253}-\u{225F}] |
    [\u{2262}-\u{2263}] |
    [\u{2268}-\u{2269}] |
    [\u{226C}-\u{226D}] |
    [\u{2270}-\u{2281}] |
    [\u{2284}-\u{2285}] |
    [\u{2288}-\u{2294}] |
    [\u{2296}-\u{2298}] |
    [\u{229A}-\u{22A4}] |
    [\u{22A6}-\u{22BE}] |
    [\u{22C0}-\u{2311}] |
    [\u{2313}-\u{2319}] |
    [\u{231C}-\u{2328}] |
    [\u{232B}-\u{23E8}] |
    [\u{23ED}-\u{23EF}] |
    [\u{23F1}-\u{23F2}] |
    [\u{23F4}-\u{2426}] |
    [\u{2440}-\u{244A}] |
    \u{24EA} |
    [\u{254C}-\u{254F}] |
    [\u{2574}-\u{257F}] |
    [\u{2590}-\u{2591}] |
    [\u{2596}-\u{259F}] |
    \u{25A2} |
    [\u{25AA}-\u{25B1}] |
    [\u{25B4}-\u{25B5}] |
    [\u{25B8}-\u{25BB}] |
    [\u{25BE}-\u{25BF}] |
    [\u{25C2}-\u{25C5}] |
    [\u{25C9}-\u{25CA}] |
    [\u{25CC}-\u{25CD}] |
    [\u{25D2}-\u{25E1}] |
    [\u{25E6}-\u{25EE}] |
    [\u{25F0}-\u{25FC}] |
    [\u{25FF}-\u{2604}] |
    [\u{2607}-\u{2608}] |
    [\u{260A}-\u{260D}] |
    [\u{2610}-\u{2613}] |
    [\u{2616}-\u{261B}] |
    \u{261D} |
    [\u{261F}-\u{263F}] |
    \u{2641} |
    [\u{2643}-\u{2647}] |
    [\u{2654}-\u{265F}] |
    \u{2662} |
    \u{2666} |
    \u{266B} |
    \u{266E} |
    [\u{2670}-\u{267E}] |
    [\u{2680}-\u{2692}] |
    [\u{2694}-\u{269D}] |
    \u{26A0} |
    [\u{26A2}-\u{26A9}] |
    [\u{26AC}-\u{26BC}] |
    [\u{26C0}-\u{26C3}] |
    \u{26E2} |
    [\u{26E4}-\u{26E7}] |
    [\u{2700}-\u{2704}] |
    [\u{2706}-\u{2709}] |
    [\u{270C}-\u{2727}] |
    [\u{2729}-\u{273C}] |
    [\u{273E}-\u{274B}] |
    \u{274D} |
    [\u{274F}-\u{2752}] |
    \u{2756} |
    [\u{2758}-\u{2775}] |
    [\u{2780}-\u{2794}] |
    [\u{2798}-\u{27AF}] |
    [\u{27B1}-\u{27BE}] |
    [\u{27C0}-\u{27E5}] |
    [\u{27EE}-\u{2984}] |
    [\u{2987}-\u{2B1A}] |
    [\u{2B1D}-\u{2B4F}] |
    [\u{2B51}-\u{2B54}] |
    [\u{2B5A}-\u{2B73}] |
    [\u{2B76}-\u{2B95}] |
    [\u{2B98}-\u{2C2E}] |
    [\u{2C30}-\u{2C5E}] |
    [\u{2C60}-\u{2CF3}] |
    [\u{2CF9}-\u{2D25}] |
    \u{2D27} |
    \u{2D2D} |
    [\u{2D30}-\u{2D67}] |
    [\u{2D6F}-\u{2D70}] |
    [\u{2D7F}-\u{2D96}] |
    [\u{2DA0}-\u{2DA6}] |
    [\u{2DA8}-\u{2DAE}] |
    [\u{2DB0}-\u{2DB6}] |
    [\u{2DB8}-\u{2DBE}] |
    [\u{2DC0}-\u{2DC6}] |
    [\u{2DC8}-\u{2DCE}] |
    [\u{2DD0}-\u{2DD6}] |
    [\u{2DD8}-\u{2DDE}] |
    [\u{2DE0}-\u{2E4F}] |
    \u{303F} |
    [\u{4DC0}-\u{4DFF}] |
    [\u{A4D0}-\u{A62B}] |
    [\u{A640}-\u{A6F7}] |
    [\u{A700}-\u{A7BF}] |
    [\u{A7C2}-\u{A7C6}] |
    [\u{A7F7}-\u{A82B}] |
    [\u{A830}-\u{A839}] |
    [\u{A840}-\u{A877}] |
    [\u{A880}-\u{A8C5}] |
    [\u{A8CE}-\u{A8D9}] |
    [\u{A8E0}-\u{A953}] |
    \u{A95F} |
    [\u{A980}-\u{A9CD}] |
    [\u{A9CF}-\u{A9D9}] |
    [\u{A9DE}-\u{A9FE}] |
    [\u{AA00}-\u{AA36}] |
    [\u{AA40}-\u{AA4D}] |
    [\u{AA50}-\u{AA59}] |
    [\u{AA5C}-\u{AAC2}] |
    [\u{AADB}-\u{AAF6}] |
    [\u{AB01}-\u{AB06}] |
    [\u{AB09}-\u{AB0E}] |
    [\u{AB11}-\u{AB16}] |
    [\u{AB20}-\u{AB26}] |
    [\u{AB28}-\u{AB2E}] |
    [\u{AB30}-\u{AB67}] |
    [\u{AB70}-\u{ABED}] |
    [\u{ABF0}-\u{ABF9}] |
    [\u{D7B0}-\u{D7C6}] |
    [\u{D7CB}-\u{D7FB}] |
    [\u{FB00}-\u{FB06}] |
    [\u{FB13}-\u{FB17}] |
    [\u{FB1D}-\u{FB36}] |
    [\u{FB38}-\u{FB3C}] |
    \u{FB3E} |
    [\u{FB40}-\u{FB41}] |
    [\u{FB43}-\u{FB44}] |
    [\u{FB46}-\u{FBC1}] |
    [\u{FBD3}-\u{FD3F}] |
    [\u{FD50}-\u{FD8F}] |
    [\u{FD92}-\u{FDC7}] |
    [\u{FDF0}-\u{FDFD}] |
    [\u{FE20}-\u{FE2F}] |
    [\u{FE70}-\u{FE74}] |
    [\u{FE76}-\u{FEFC}] |
    \u{FEFF} |
    [\u{FFF9}-\u{FFFC}] |
    [\u{10000}-\u{1000B}] |
    [\u{1000D}-\u{10026}] |
    [\u{10028}-\u{1003A}] |
    [\u{1003C}-\u{1003D}] |
    [\u{1003F}-\u{1004D}] |
    [\u{10050}-\u{1005D}] |
    [\u{10080}-\u{100FA}] |
    [\u{10100}-\u{10102}] |
    [\u{10107}-\u{10133}] |
    [\u{10137}-\u{1018E}] |
    [\u{10190}-\u{1019B}] |
    \u{101A0} |
    [\u{101D0}-\u{101FD}] |
    [\u{10280}-\u{1029C}] |
    [\u{102A0}-\u{102D0}] |
    [\u{102E0}-\u{102FB}] |
    [\u{10300}-\u{10323}] |
    [\u{1032D}-\u{1034A}] |
    [\u{10350}-\u{1037A}] |
    [\u{10380}-\u{1039D}] |
    [\u{1039F}-\u{103C3}] |
    [\u{103C8}-\u{103D5}] |
    [\u{10400}-\u{1049D}] |
    [\u{104A0}-\u{104A9}] |
    [\u{104B0}-\u{104D3}] |
    [\u{104D8}-\u{104FB}] |
    [\u{10500}-\u{10527}] |
    [\u{10530}-\u{10563}] |
    \u{1056F} |
    [\u{10600}-\u{10736}] |
    [\u{10740}-\u{10755}] |
    [\u{10760}-\u{10767}] |
    [\u{10800}-\u{10805}] |
    \u{10808} |
    [\u{1080A}-\u{10835}] |
    [\u{10837}-\u{10838}] |
    \u{1083C} |
    [\u{1083F}-\u{10855}] |
    [\u{10857}-\u{1089E}] |
    [\u{108A7}-\u{108AF}] |
    [\u{108E0}-\u{108F2}] |
    [\u{108F4}-\u{108F5}] |
    [\u{108FB}-\u{1091B}] |
    [\u{1091F}-\u{10939}] |
    \u{1093F} |
    [\u{10980}-\u{109B7}] |
    [\u{109BC}-\u{109CF}] |
    [\u{109D2}-\u{10A03}] |
    [\u{10A05}-\u{10A06}] |
    [\u{10A0C}-\u{10A13}] |
    [\u{10A15}-\u{10A17}] |
    [\u{10A19}-\u{10A35}] |
    [\u{10A38}-\u{10A3A}] |
    [\u{10A3F}-\u{10A48}] |
    [\u{10A50}-\u{10A58}] |
    [\u{10A60}-\u{10A9F}] |
    [\u{10AC0}-\u{10AE6}] |
    [\u{10AEB}-\u{10AF6}] |
    [\u{10B00}-\u{10B35}] |
    [\u{10B39}-\u{10B55}] |
    [\u{10B58}-\u{10B72}] |
    [\u{10B78}-\u{10B91}] |
    [\u{10B99}-\u{10B9C}] |
    [\u{10BA9}-\u{10BAF}] |
    [\u{10C00}-\u{10C48}] |
    [\u{10C80}-\u{10CB2}] |
    [\u{10CC0}-\u{10CF2}] |
    [\u{10CFA}-\u{10D27}] |
    [\u{10D30}-\u{10D39}] |
    [\u{10E60}-\u{10E7E}] |
    [\u{10F00}-\u{10F27}] |
    [\u{10F30}-\u{10F59}] |
    [\u{10FE0}-\u{10FF6}] |
    [\u{11000}-\u{1104D}] |
    [\u{11052}-\u{1106F}] |
    [\u{1107F}-\u{110C1}] |
    \u{110CD} |
    [\u{110D0}-\u{110E8}] |
    [\u{110F0}-\u{110F9}] |
    [\u{11100}-\u{11134}] |
    [\u{11136}-\u{11146}] |
    [\u{11150}-\u{11176}] |
    [\u{11180}-\u{111CD}] |
    [\u{111D0}-\u{111DF}] |
    [\u{111E1}-\u{111F4}] |
    [\u{11200}-\u{11211}] |
    [\u{11213}-\u{1123E}] |
    [\u{11280}-\u{11286}] |
    \u{11288} |
    [\u{1128A}-\u{1128D}] |
    [\u{1128F}-\u{1129D}] |
    [\u{1129F}-\u{112A9}] |
    [\u{112B0}-\u{112EA}] |
    [\u{112F0}-\u{112F9}] |
    [\u{11300}-\u{11303}] |
    [\u{11305}-\u{1130C}] |
    [\u{1130F}-\u{11310}] |
    [\u{11313}-\u{11328}] |
    [\u{1132A}-\u{11330}] |
    [\u{11332}-\u{11333}] |
    [\u{11335}-\u{11339}] |
    [\u{1133B}-\u{11344}] |
    [\u{11347}-\u{11348}] |
    [\u{1134B}-\u{1134D}] |
    \u{11350} |
    \u{11357} |
    [\u{1135D}-\u{11363}] |
    [\u{11366}-\u{1136C}] |
    [\u{11370}-\u{11374}] |
    [\u{11400}-\u{11459}] |
    \u{1145B} |
    [\u{1145D}-\u{1145F}] |
    [\u{11480}-\u{114C7}] |
    [\u{114D0}-\u{114D9}] |
    [\u{11580}-\u{115B5}] |
    [\u{115B8}-\u{115DD}] |
    [\u{11600}-\u{11644}] |
    [\u{11650}-\u{11659}] |
    [\u{11660}-\u{1166C}] |
    [\u{11680}-\u{116B8}] |
    [\u{116C0}-\u{116C9}] |
    [\u{11700}-\u{1171A}] |
    [\u{1171D}-\u{1172B}] |
    [\u{11730}-\u{1173F}] |
    [\u{11800}-\u{1183B}] |
    [\u{118A0}-\u{118F2}] |
    \u{118FF} |
    [\u{119A0}-\u{119A7}] |
    [\u{119AA}-\u{119D7}] |
    [\u{119DA}-\u{119E4}] |
    [\u{11A00}-\u{11A47}] |
    [\u{11A50}-\u{11AA2}] |
    [\u{11AC0}-\u{11AF8}] |
    [\u{11C00}-\u{11C08}] |
    [\u{11C0A}-\u{11C36}] |
    [\u{11C38}-\u{11C45}] |
    [\u{11C50}-\u{11C6C}] |
    [\u{11C70}-\u{11C8F}] |
    [\u{11C92}-\u{11CA7}] |
    [\u{11CA9}-\u{11CB6}] |
    [\u{11D00}-\u{11D06}] |
    [\u{11D08}-\u{11D09}] |
    [\u{11D0B}-\u{11D36}] |
    \u{11D3A} |
    [\u{11D3C}-\u{11D3D}] |
    [\u{11D3F}-\u{11D47}] |
    [\u{11D50}-\u{11D59}] |
    [\u{11D60}-\u{11D65}] |
    [\u{11D67}-\u{11D68}] |
    [\u{11D6A}-\u{11D8E}] |
    [\u{11D90}-\u{11D91}] |
    [\u{11D93}-\u{11D98}] |
    [\u{11DA0}-\u{11DA9}] |
    [\u{11EE0}-\u{11EF8}] |
    [\u{11FC0}-\u{11FF1}] |
    [\u{11FFF}-\u{12399}] |
    [\u{12400}-\u{1246E}] |
    [\u{12470}-\u{12474}] |
    [\u{12480}-\u{12543}] |
    [\u{13000}-\u{1342E}] |
    [\u{13430}-\u{13438}] |
    [\u{14400}-\u{14646}] |
    [\u{16800}-\u{16A38}] |
    [\u{16A40}-\u{16A5E}] |
    [\u{16A60}-\u{16A69}] |
    [\u{16A6E}-\u{16A6F}] |
    [\u{16AD0}-\u{16AED}] |
    [\u{16AF0}-\u{16AF5}] |
    [\u{16B00}-\u{16B45}] |
    [\u{16B50}-\u{16B59}] |
    [\u{16B5B}-\u{16B61}] |
    [\u{16B63}-\u{16B77}] |
    [\u{16B7D}-\u{16B8F}] |
    [\u{16E40}-\u{16E9A}] |
    [\u{16F00}-\u{16F4A}] |
    [\u{16F4F}-\u{16F87}] |
    [\u{16F8F}-\u{16F9F}] |
    [\u{1BC00}-\u{1BC6A}] |
    [\u{1BC70}-\u{1BC7C}] |
    [\u{1BC80}-\u{1BC88}] |
    [\u{1BC90}-\u{1BC99}] |
    [\u{1BC9C}-\u{1BCA3}] |
    [\u{1D000}-\u{1D0F5}] |
    [\u{1D100}-\u{1D126}] |
    [\u{1D129}-\u{1D1E8}] |
    [\u{1D200}-\u{1D245}] |
    [\u{1D2E0}-\u{1D2F3}] |
    [\u{1D300}-\u{1D356}] |
    [\u{1D360}-\u{1D378}] |
    [\u{1D400}-\u{1D454}] |
    [\u{1D456}-\u{1D49C}] |
    [\u{1D49E}-\u{1D49F}] |
    \u{1D4A2} |
    [\u{1D4A5}-\u{1D4A6}] |
    [\u{1D4A9}-\u{1D4AC}] |
    [\u{1D4AE}-\u{1D4B9}] |
    \u{1D4BB} |
    [\u{1D4BD}-\u{1D4C3}] |
    [\u{1D4C5}-\u{1D505}] |
    [\u{1D507}-\u{1D50A}] |
    [\u{1D50D}-\u{1D514}] |
    [\u{1D516}-\u{1D51C}] |
    [\u{1D51E}-\u{1D539}] |
    [\u{1D53B}-\u{1D53E}] |
    [\u{1D540}-\u{1D544}] |
    \u{1D546} |
    [\u{1D54A}-\u{1D550}] |
    [\u{1D552}-\u{1D6A5}] |
    [\u{1D6A8}-\u{1D7CB}] |
    [\u{1D7CE}-\u{1DA8B}] |
    [\u{1DA9B}-\u{1DA9F}] |
    [\u{1DAA1}-\u{1DAAF}] |
    [\u{1E000}-\u{1E006}] |
    [\u{1E008}-\u{1E018}] |
    [\u{1E01B}-\u{1E021}] |
    [\u{1E023}-\u{1E024}] |
    [\u{1E026}-\u{1E02A}] |
    [\u{1E100}-\u{1E12C}] |
    [\u{1E130}-\u{1E13D}] |
    [\u{1E140}-\u{1E149}] |
    [\u{1E14E}-\u{1E14F}] |
    [\u{1E2C0}-\u{1E2F9}] |
    \u{1E2FF} |
    [\u{1E800}-\u{1E8C4}] |
    [\u{1E8C7}-\u{1E8D6}] |
    [\u{1E900}-\u{1E94B}] |
    [\u{1E950}-\u{1E959}] |
    [\u{1E95E}-\u{1E95F}] |
    [\u{1EC71}-\u{1ECB4}] |
    [\u{1ED01}-\u{1ED3D}] |
    [\u{1EE00}-\u{1EE03}] |
    [\u{1EE05}-\u{1EE1F}] |
    [\u{1EE21}-\u{1EE22}] |
    \u{1EE24} |
    \u{1EE27} |
    [\u{1EE29}-\u{1EE32}] |
    [\u{1EE34}-\u{1EE37}] |
    \u{1EE39} |
    \u{1EE3B} |
    \u{1EE42} |
    \u{1EE47} |
    \u{1EE49} |
    \u{1EE4B} |
    [\u{1EE4D}-\u{1EE4F}] |
    [\u{1EE51}-\u{1EE52}] |
    \u{1EE54} |
    \u{1EE57} |
    \u{1EE59} |
    \u{1EE5B} |
    \u{1EE5D} |
    \u{1EE5F} |
    [\u{1EE61}-\u{1EE62}] |
    \u{1EE64} |
    [\u{1EE67}-\u{1EE6A}] |
    [\u{1EE6C}-\u{1EE72}] |
    [\u{1EE74}-\u{1EE77}] |
    [\u{1EE79}-\u{1EE7C}] |
    \u{1EE7E} |
    [\u{1EE80}-\u{1EE89}] |
    [\u{1EE8B}-\u{1EE9B}] |
    [\u{1EEA1}-\u{1EEA3}] |
    [\u{1EEA5}-\u{1EEA9}] |
    [\u{1EEAB}-\u{1EEBB}] |
    [\u{1EEF0}-\u{1EEF1}] |
    [\u{1F000}-\u{1F003}] |
    [\u{1F005}-\u{1F02B}] |
    [\u{1F030}-\u{1F093}] |
    [\u{1F0A0}-\u{1F0AE}] |
    [\u{1F0B1}-\u{1F0BF}] |
    [\u{1F0C1}-\u{1F0CE}] |
    [\u{1F0D1}-\u{1F0F5}] |
    [\u{1F10B}-\u{1F10C}] |
    [\u{1F12E}-\u{1F12F}] |
    [\u{1F16A}-\u{1F16C}] |
    [\u{1F1E6}-\u{1F1FF}] |
    [\u{1F321}-\u{1F32C}] |
    \u{1F336} |
    \u{1F37D} |
    [\u{1F394}-\u{1F39F}] |
    [\u{1F3CB}-\u{1F3CE}] |
    [\u{1F3D4}-\u{1F3DF}] |
    [\u{1F3F1}-\u{1F3F3}] |
    [\u{1F3F5}-\u{1F3F7}] |
    \u{1F43F} |
    \u{1F441} |
    [\u{1F4FD}-\u{1F4FE}] |
    [\u{1F53E}-\u{1F54A}] |
    \u{1F54F} |
    [\u{1F568}-\u{1F579}] |
    [\u{1F57B}-\u{1F594}] |
    [\u{1F597}-\u{1F5A3}] |
    [\u{1F5A5}-\u{1F5FA}] |
    [\u{1F650}-\u{1F67F}] |
    [\u{1F6C6}-\u{1F6CB}] |
    [\u{1F6CD}-\u{1F6CF}] |
    [\u{1F6D3}-\u{1F6D4}] |
    [\u{1F6E0}-\u{1F6EA}] |
    [\u{1F6F0}-\u{1F6F3}] |
    [\u{1F700}-\u{1F773}] |
    [\u{1F780}-\u{1F7D8}] |
    [\u{1F800}-\u{1F80B}] |
    [\u{1F810}-\u{1F847}] |
    [\u{1F850}-\u{1F859}] |
    [\u{1F860}-\u{1F887}] |
    [\u{1F890}-\u{1F8AD}] |
    [\u{1F900}-\u{1F90B}] |
    [\u{1FA00}-\u{1FA53}] |
    [\u{1FA60}-\u{1FA6D}] |
    \u{E0001} |
    [\u{E0020}-\u{E007F}]
  )/x
end
