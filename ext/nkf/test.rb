#!/usr/local/bin/ruby
#
# nkf test program for nkf-2
#
# $Id$
#
#    Shinji KONO <kono@ie.u-ryukyu.ac.jp>
# Sun Aug 18 12:25:40 JST 1996
# Sun Nov  8 00:16:06 JST 1998
#
# This is useful when you add new patch on nkf.
# Since this test is too strict, faileurs may not mean
# wrong conversion. 
#
# nkf 1.5 differs on MIME decoding
# nkf 1.4 passes Basic Conversion tests
# nkf PDS version passes Basic Conversion tests  using "nkf -iB -oB "
#

$counter = 0
def result(result, message = nil)
  $counter += 1
  printf("%s %d%s\n",
	 result ? 'ok' : 'no', 
	 $counter, 
	 message ? ' ... ' + message : '')
end

begin
  require 'nkf'
  include NKF
rescue LoadError
  result(false)
end
result(true)

if nkf('-me', '1')
  result(true);
else
  result(false);
end

output = nkf('-e', "\033\$@#1#3#2%B")
if output
  # print output, "\n"
  result(true, output)
else
  result(false)
end

output = nkf('-Zj', "\033\$@#1#3#2%B")
if output
  # print output, "\n"
  result(true, output)
else
  result(false)
end

output = "\244\306 " * 1024
old =  output.length
output = nkf("-j", output)
if output
  # print output, "\n"
  result(true, "#{old} #{output.length}")
else
    result(false)
end


$detail = false
def test(opt, input, expects)
  print "\nINPUT:\n", input if $detail
  print "\nEXPECT:\n", expects.to_s if $detail
  result = nkf(opt, input)
  result.delete!(' ') if opt.include?('-m')
  print "\nGOT:\n", result if $detail

  expects.each do |e|
    e.delete!(' ') if opt.include?('-m')
    if result == e then
      puts "Ok"
      return result
    end
  end
  puts "Fail"
  puts result.unpack('H*').first
  puts expects.map{|x|x.unpack('H*').first}.join("\n\n")
end


$example = Hash.new


# Basic Conversion
print "\nBasic Conversion test\n\n";

# I gave up simple literal quote because there are big difference
# on perl4 and perl5 on literal quote. Of course we cannot use
# jperl.

$example['jis'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@&R1"(3DQ(3%^2R%+?D]3&RA"(%-E8V]N9"!3=&%G92`;
M)$)0)TU:&RA"($AI<F%G86YA(!LD0B0B)"0D)B0H)"HD;R1R)',;*$(*2V%T
M86MA;F$@&R1")2(E)"4F)2@E*B5O)7(E<QLH0B!+:6=O=2`;)$(A)B%G(S`C
/029!)E@G(B=!*$`;*$(*
eofeof

$example['sjis'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@@5B)0(F>ED"6GIAR(%-E8V]N9"!3=&%G92"8I9=Y($AI
M<F%G86YA((*@@J*"I(*F@JB"[8+P@O$*2V%T86MA;F$@@T&#0X-%@T>#28./
>@Y*#DR!+:6=O=2"!18&'@D^"8(._@]:$081@A+X*
eofeof

$example['euc'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@H;FQH;'^RZ'+_L_3(%-E8V]N9"!3=&%G92#0I\W:($AI
M<F%G86YA(*2BI*2DIJ2HI*JD[Z3RI/,*2V%T86MA;F$@I:*EI*6FI:BEJJ7O
>I?*E\R!+:6=O=2"AIJ'GH["CP:;!IMBGHJ?!J,`*
eofeof

$example['utf8'] = <<'eofeof'.unpack('u')[0]
M[[N_1FER<W0@4W1A9V4@XX"%Z9FBY;^<YK.5YKJ`Z(65(%-E8V]N9"!3=&%G
M92#DN+SI@:4@2&ER86=A;F$@XX&"XX&$XX&&XX&(XX&*XX*/XX*2XX*3"DMA
M=&%K86YA(.."HN."I.."IN."J.."JN.#K^.#LN.#LR!+:6=O=2#C@[OBB)[O
1O)#OO*'.L<^)T)'0K^*5@@H`
eofeof

$example['utf8N'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@XX"%Z9FBY;^<YK.5YKJ`Z(65(%-E8V]N9"!3=&%G92#D
MN+SI@:4@2&ER86=A;F$@XX&"XX&$XX&&XX&(XX&*XX*/XX*2XX*3"DMA=&%K
M86YA(.."HN."I.."IN."J.."JN.#K^.#LN.#LR!+:6=O=2#C@[OBB)[OO)#O
.O*'.L<^)T)'0K^*5@@H`
eofeof

$example['u16L'] = <<'eofeof'.unpack('u')[0]
M__Y&`&D`<@!S`'0`(`!3`'0`80!G`&4`(``%,&*6W%_5;(!N58$@`%,`90!C
M`&\`;@!D`"``4P!T`&$`9P!E`"``/$YED"``2`!I`'(`80!G`&$`;@!A`"``
M0C!$,$8P2#!*,(\PDC"3,`H`2P!A`'0`80!K`&$`;@!A`"``HC"D,*8PJ#"J
I,.\P\C#S,"``2P!I`&<`;P!U`"``^S`>(A#_(?^Q`\D#$00O!$(E"@``
eofeof

$example['u16L0'] = <<'eofeof'.unpack('u')[0]
M1@!I`'(`<P!T`"``4P!T`&$`9P!E`"``!3!BEMQ?U6R`;E6!(`!3`&4`8P!O
M`&X`9``@`%,`=`!A`&<`90`@`#Q.99`@`$@`:0!R`&$`9P!A`&X`80`@`$(P
M1#!&,$@P2C"/,)(PDS`*`$L`80!T`&$`:P!A`&X`80`@`*(PI#"F,*@PJC#O
G,/(P\S`@`$L`:0!G`&\`=0`@`/LP'B(0_R'_L0/)`Q$$+P1")0H`
eofeof

$example['u16B'] = <<'eofeof'.unpack('u')[0]
M_O\`1@!I`'(`<P!T`"``4P!T`&$`9P!E`"`P!99B7]QLU6Z`@54`(`!3`&4`
M8P!O`&X`9``@`%,`=`!A`&<`90`@3CR090`@`$@`:0!R`&$`9P!A`&X`80`@
M,$(P1#!&,$@P2C"/,)(PDP`*`$L`80!T`&$`:P!A`&X`80`@,*(PI#"F,*@P
IJC#O,/(P\P`@`$L`:0!G`&\`=0`@,/LB'O\0_R$#L0/)!!$$+R5"``H`
eofeof

$example['u16B0'] = <<'eofeof'.unpack('u')[0]
M`$8`:0!R`',`=``@`%,`=`!A`&<`90`@,`668E_<;-5N@(%5`"``4P!E`&,`
M;P!N`&0`(`!3`'0`80!G`&4`($X\D&4`(`!(`&D`<@!A`&<`80!N`&$`(#!"
M,$0P1C!(,$HPCS"2,),`"@!+`&$`=`!A`&L`80!N`&$`(#"B,*0PIC"H,*HP
G[S#R,/,`(`!+`&D`9P!O`'4`(##[(A[_$/\A`[$#R001!"\E0@`*
eofeof

$example['jis1'] = <<'eofeof'.unpack('u')[0]
M&R1";3%Q<$$L&RA""ALD0F4Z3F\;*$(*&R1"<FT;*$()&R1"/F5.3D]+&RA"
#"0D*
eofeof

$example['sjis1'] = <<'eofeof'.unpack('u')[0]
8YU#ID)%+"N-9E^T*Z>L)C^.7S)AJ"0D*
eofeof

$example['euc1'] = <<'eofeof'.unpack('u')[0]
8[;'Q\,&L"N6ZSN\*\NT)ON7.SL_+"0D*
eofeof

$example['utf1'] = <<'eofeof'.unpack('u')[0]
AZ+J%Z:N/Z8JM"N>VNNFZEPKIM(D)Y+B*Z:"8Y+J8"0D*
eofeof

$example['jis2'] = <<'eofeof'.unpack('u')[0]
+&R1".EA&(QLH0@H`
eofeof

$example['sjis2'] = <<'eofeof'.unpack('u')[0]
%C=:3H0H`
eofeof

$example['euc2'] = <<'eofeof'.unpack('u')[0]
%NMC&HPH`
eofeof

$example['utf2'] = <<'eofeof'.unpack('u')[0]
'YI:.Z)>D"@``
eofeof

# From JIS

print "JIS  to JIS ... ";test("-j",$example['jis'],[$example['jis']])
print "JIS  to SJIS... ";test("-s",$example['jis'],[$example['sjis']])
print "JIS  to EUC ... ";test("-e",$example['jis'],[$example['euc']])
print "JIS  to UTF8... ";test("-w",$example['jis'],[$example['utf8N']])
print "JIS  to U16L... ";test("-w16L",$example['jis'],[$example['u16L']])
print "JIS  to U16B... ";test("-w16B",$example['jis'],[$example['u16B']])

# From SJIS

print "SJIS to JIS ... ";test("-j",$example['sjis'],[$example['jis']])
print "SJIS to SJIS... ";test("-s",$example['sjis'],[$example['sjis']])
print "SJIS to EUC ... ";test("-e",$example['sjis'],[$example['euc']])
print "SJIS to UTF8... ";test("-w",$example['sjis'],[$example['utf8N']])
print "SJIS to U16L... ";test("-w16L",$example['sjis'],[$example['u16L']])
print "SJIS to U16B... ";test("-w16B",$example['sjis'],[$example['u16B']])

# From EUC

print "EUC  to JIS ... ";test("-j",$example['euc'],[$example['jis']])
print "EUC  to SJIS... ";test("-s",$example['euc'],[$example['sjis']])
print "EUC  to EUC ... ";test("-e",$example['euc'],[$example['euc']])
print "EUC  to UTF8... ";test("-w",$example['euc'],[$example['utf8N']])
print "EUC  to U16L... ";test("-w16L",$example['euc'],[$example['u16L']])
print "EUC  to U16B... ";test("-w16B",$example['euc'],[$example['u16B']])

# From UTF8

print "UTF8 to JIS ... ";test("-j",	$example['utf8N'],[$example['jis']])
print "UTF8 to SJIS... ";test("-s",	$example['utf8N'],[$example['sjis']])
print "UTF8 to EUC ... ";test("-e",	$example['utf8N'],[$example['euc']])
print "UTF8 to UTF8N.. ";test("-w",	$example['utf8N'],[$example['utf8N']])
print "UTF8 to UTF8... ";test("-w8",	$example['utf8N'],[$example['utf8']])
print "UTF8 to UTF8N.. ";test("-w80",	$example['utf8N'],[$example['utf8N']])
print "UTF8 to U16L... ";test("-w16L",	$example['utf8N'],[$example['u16L']])
print "UTF8 to U16L0.. ";test("-w16L0",	$example['utf8N'],[$example['u16L0']])
print "UTF8 to U16B... ";test("-w16B",	$example['utf8N'],[$example['u16B']])
print "UTF8 to U16B0.. ";test("-w16B0",	$example['utf8N'],[$example['u16B0']])



# From JIS

print "JIS  to JIS ... ";test("-j",$example['jis1'],[$example['jis1']])
print "JIS  to SJIS... ";test("-s",$example['jis1'],[$example['sjis1']])
print "JIS  to EUC ... ";test("-e",$example['jis1'],[$example['euc1']])
print "JIS  to UTF8... ";test("-w",$example['jis1'],[$example['utf1']])

# From SJIS

print "SJIS to JIS ... ";test("-j",$example['sjis1'],[$example['jis1']])
print "SJIS to SJIS... ";test("-s",$example['sjis1'],[$example['sjis1']])
print "SJIS to EUC ... ";test("-e",$example['sjis1'],[$example['euc1']])
print "SJIS to UTF8... ";test("-w",$example['sjis1'],[$example['utf1']])

# From EUC

print "EUC  to JIS ... ";test("-j",$example['euc1'],[$example['jis1']])
print "EUC  to SJIS... ";test("-s",$example['euc1'],[$example['sjis1']])
print "EUC  to EUC ... ";test("-e",$example['euc1'],[$example['euc1']])
print "EUC  to UTF8... ";test("-w",$example['euc1'],[$example['utf1']])

# From UTF8

print "UTF8 to JIS ... ";test("-j",$example['utf1'],[$example['jis1']])
print "UTF8 to SJIS... ";test("-s",$example['utf1'],[$example['sjis1']])
print "UTF8 to EUC ... ";test("-e",$example['utf1'],[$example['euc1']])
print "UTF8 to UTF8... ";test("-w",$example['utf1'],[$example['utf1']])

# Ambigous Case

$example['amb'] = <<'eofeof'.unpack('u')[0]
MI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&E
MPK"QI<*PL:7"L+&EPK"QI<(*I<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*P
ML:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<(*I<*PL:7"L+&E
MPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"
ML+&EPK"QI<(*I<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"Q
MI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<(*I<*PL:7"L+&EPK"QI<*PL:7"
ML+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<(*
eofeof

$example['amb.euc'] = <<'eofeof'.unpack('u')[0]
M&R1")4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25"
M,#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*&R1")4(P,25",#$E0C`Q)4(P,25"
M,#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;
M*$(*&R1")4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P
M,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*&R1")4(P,25",#$E0C`Q)4(P
M,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q
M)4(;*$(*&R1")4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q
>)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*
eofeof

$example['amb.sjis'] = <<'eofeof'.unpack('u')[0]
M&RA))4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25"
M,#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*&RA))4(P,25",#$E0C`Q)4(P,25"
M,#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;
M*$(*&RA))4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P
M,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*&RA))4(P,25",#$E0C`Q)4(P
M,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q
M)4(;*$(*&RA))4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q
>)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*
eofeof

print "Ambiguous Case. ";
    test("-j",$example['amb'],[$example['amb.euc']])

# Input assumption

print "SJIS  Input assumption ";
    test("-jSx",$example['amb'],[$example['amb.sjis']])

# Broken JIS

print "Broken JIS ";
    $input = $example['jis'];
    $input.gsub!("\033",'')
    test("-Be",$input,[$example['euc']]);
print "Broken JIS is safe on Normal JIS? ";
    $input = $example['jis'];
    test("-Be",$input,[$example['euc']]);

# test_data/cp932

$example['test_data/cp932'] = <<'eofeof'.unpack('u')[0]
%^D`@_$L`
eofeof

$example['test_data/cp932.ans'] = <<'eofeof'.unpack('u')[0]
%_/$@_.X`
eofeof

print "test_data/cp932    ";
    test("-eS",$example['test_data/cp932'],[$example['test_data/cp932.ans']])

# test_data/cp932inv
print "test_data/cp932inv    ";
    test("-sE --cp932inv",$example['test_data/cp932.ans'],[$example['test_data/cp932']])

# test_data/no-cp932inv

$example['test_data/no-cp932inv.ans'] = <<'eofeof'.unpack('u')[0]
%[N\@[NP`
eofeof

print "test_data/no-cp932inv    ";
test("-sE --no-cp932",$example['test_data/cp932.ans'],[$example['test_data/no-cp932inv.ans']])

# test_data/irv

# $example['test_data/irv'] = <<'eofeof'.unpack('u')[0]
# %#B`/(!L`
# eofeof
# 
# $example['test_data/irv.ans'] = <<'eofeof'.unpack('u')[0]
# %#B`/(!L`
# eofeof
# 
# print "test_data/irv    ";
#    test("-wE",$example['test_data/irv'],[$example['test_data/irv.ans']])


# UCS Mapping Test
print "\n\nUCS Mapping Test\n";

print "Shift_JIS to UTF-16\n";
$example['ms_ucs_map_1_sjis'] = "\x81\x60\x81\x61\x81\x7C\x81\x91\x81\x92\x81\xCA";
$example['ms_ucs_map_1_utf16'] = "\x30\x1C\x20\x16\x22\x12\x00\xA2\x00\xA3\x00\xAC";
$example['ms_ucs_map_1_utf16_ms'] = "\xFF\x5E\x22\x25\xFF\x0D\xFF\xE0\xFF\xE1\xFF\xE2";

print "Normal UCS Mapping : ";
    test("-w16B0 -S",$example['ms_ucs_map_1_sjis'],[$example['ms_ucs_map_1_utf16']])

print "Microsoft UCS Mapping : ";
    test("-w16B0 -S --ms-ucs-map",$example['ms_ucs_map_1_sjis'],[$example['ms_ucs_map_1_utf16_ms']])

print"\n";

# X0201 仮名
# X0201->X0208 conversion
# X0208 aphabet -> ASCII
# X0201 相互変換

print "\nX0201 test\n\n";

$example['x0201.sjis'] = <<'eofeof'.unpack('u')[0]
MD5.*<(-*@TR#3H-0@U*#2X--@T^#48-3"I%3B7""8()A@F*"8X)D@F6"9H*!
M@H*"@X*$@H6"AH*'"I%3BTR-AH%)@9>!E(&0@9.!3X&5@9:!:8%J@7R!>X&!
M@6V!;H%O@7"!CPJ4O(IPMK>X/;FZMMZWWKC>N=ZZWH+&"I2\BG#*W\O?S-_-
MW\[?M]^QW@K*W\O?S`IH86YK86MU(,K?R]_,I`K*W\O?S-VA"I2\BG""S(SC
!"@!"
eofeof

$example['x0201.euc'] = <<'eofeof'.unpack('u')[0]
MP;2ST:6KI:VEKZ6QI;.EK*6NI;"ELJ6T"L&TL=&CP:/"H\.CQ*/%H\:CQZ/A
MH^*CXZ/DH^6CYJ/G"L&TM:VYYJ&JH?>A]*'PH?.AL*'UH?:ARJ'+H=VAW*'A
MH<ZASZ'0H=&A[PK(OK/1CK:.MXZX/8ZYCKJ.MH[>CK>.WHZXCMZ.N8[>CKJ.
MWJ3("LB^L]&.RH[?CLN.WX[,CM^.S8[?CLZ.WXZWCM^.L8[>"H[*CM^.RX[?
MCLP*:&%N:V%K=2".RH[?CLN.WX[,CJ0*CLJ.WX[+CM^.S([=CJ$*R+ZST:3.
#N.4*
eofeof

$example['x0201.utf'] = <<'eofeof'.unpack('u')[0]
MY86HZ*>2XX*KXX*MXX*OXX*QXX*SXX*LXX*NXX*PXX*RXX*T"N6%J.B+L>^\
MH>^\HN^\H^^\I.^\I>^\IN^\I^^]@>^]@N^]@^^]A.^]A>^]AN^]APKEA:CH
MJ)CEC[?OO('OO*#OO(/OO(3OO(7OO+[OO(;OO(KOO(COO(GBB)+OO(OOO)WO
MO+OOO+WOO9OOO9WOOZ4*Y8V*Z*>2[[VV[[VW[[VX/>^]N>^]NN^]MN^^GN^]
MM^^^GN^]N.^^GN^]N>^^GN^]NN^^GN.!J`KEC8KHIY+OOHKOOI_OOHOOOI_O
MOHSOOI_OOHWOOI_OOH[OOI_OO;?OOI_OO;'OOIX*[[Z*[[Z?[[Z+[[Z?[[Z,
M"FAA;FMA:W4@[[Z*[[Z?[[Z+[[Z?[[Z,[[VD"N^^BN^^G^^^B^^^G^^^C.^^
2G>^]H0KEC8KHIY+C@:[EOHP*
eofeof

$example['x0201.jis'] = <<'eofeof'.unpack('u')[0]
M&R1"030S424K)2TE+R4Q)3,E+"4N)3`E,B4T&RA""ALD0D$T,5$C02-"(T,C
M1"-%(T8C1R-A(V(C8R-D(V4C9B-G&RA""ALD0D$T-2TY9B$J(7<A="%P(7,A
M,"%U(78A2B%+(5TA7"%A(4XA3R%0(5$A;QLH0@H;)$)(/C-1&RA)-C<X&RA"
M/1LH23DZ-EXW7CA>.5XZ7ALD0B1(&RA""ALD0D@^,U$;*$E*7TM?3%]-7TY?
M-U\Q7ALH0@H;*$E*7TM?3!LH0@IH86YK86MU(!LH24I?2U],)!LH0@H;*$E*
97TM?3%TA&RA""ALD0D@^,U$D3CAE&RA""@``
eofeof

$example['x0201.sosi'] = <<'eofeof'.unpack('u')[0]
M&R1"030S424K)2TE+R4Q)3,E+"4N)3`E,B4T&RA*"ALD0D$T,5$C02-"(T,C
M1"-%(T8C1R-A(V(C8R-D(V4C9B-G&RA*"ALD0D$T-2TY9B$J(7<A="%P(7,A
M,"%U(78A2B%+(5TA7"%A(4XA3R%0(5$A;QLH2@H;)$)(/C-1&RA*#C8W.`\;
M*$H]#CDZ-EXW7CA>.5XZ7@\;)$(D2!LH2@H;)$)(/C-1&RA*#DI?2U],7TU?
M3E\W7S%>#PH.2E]+7TP/&RA*"FAA;FMA:W4@#DI?2U],)`\;*$H*#DI?2U],
672$/&RA*"ALD0D@^,U$D3CAE&RA""@``
eofeof

$example['x0201.x0208'] = <<'eofeof'.unpack('u')[0]
M&R1"030S424K)2TE+R4Q)3,E+"4N)3`E,B4T&RA""ALD0D$T,5$;*$)!0D-$
M149'86)C9&5F9PH;)$)!-#4M.68;*$(A0",D)5XF*B@I+2L]6UU[?1LD0B%O
M&RA""ALD0D@^,U$E*R4M)2\;*$(]&R1")3$E,R4L)2XE,"4R)30D2!LH0@H;
M)$)(/C-1)5$E5"57)5HE724M(2PE(B$K&RA""ALD0B51)50E51LH0@IH86YK
M86MU(!LD0B51)50E52$B&RA""ALD0B51)50E525S(2,;*$(*&R1"2#XS421.
&.&4;*$(*
eofeof

# -X is necessary to allow X0201 in SJIS
# -Z convert X0208 alphabet to ASCII
print "X0201 conversion: SJIS ";
    test("-jXZ",$example['x0201.sjis'],[$example['x0201.x0208']])
print "X0201 conversion: JIS  ";
    test("-jZ",$example['x0201.jis'],[$example['x0201.x0208']])
print "X0201 conversion:SI/SO ";
    test("-jZ",$example['x0201.sosi'],[$example['x0201.x0208']])
print "X0201 conversion: EUC  ";
    test("-jZ",$example['x0201.euc'],[$example['x0201.x0208']])
print "X0201 conversion: UTF8 ";
    test("-jZ",$example['x0201.utf'],[$example['x0201.x0208']])
# -x means X0201 output
print "X0201 output: SJIS     ";
    test("-xs",$example['x0201.euc'],[$example['x0201.sjis']])
print "X0201 output: JIS      ";
    test("-xj",$example['x0201.sjis'],[$example['x0201.jis']])
print "X0201 output: EUC      ";
    test("-xe",$example['x0201.jis'],[$example['x0201.euc']])
print "X0201 output: UTF8     ";
    test("-xw",$example['x0201.jis'],[$example['x0201.utf']])

# MIME decode

print "\nMIME test\n\n";

# MIME ISO-2022-JP

$example['mime.iso2022'] = <<'eofeof'.unpack('u')[0]
M/3])4T\M,C`R,BU*4#]"/T=Y4D%.144W96E23TI566Q/4U9)1WEH2S\]"CT_
M:7-O+3(P,C(M2E`_0C]'>5)!3D5%-V5I4D]*55EL3U-624=Y:$L_/0H]/VES
M;RTR,#(R+4I0/U$_/3%")$(D1B11/3%"*$)?96YD/ST*&R1`)#TD)B0K)$H;
M*$H@/3])4T\M,C`R,BU*4#]"/T=Y4D%.144W96E23U!Y:S=D:'-O4V<]/3\]
M(&5N9"!O9B!L:6YE"CT_25-/+3(P,C(M2E`_0C]'>5)!3D5%-V5I4D]0>6LW
M9&AS;U-G/3T_/2`]/TE33RTR,#(R+4I0/T(_1WE204Y%13=E:5)/4'EK-V1H
M<V]39ST]/ST*0G)O:V5N(&-A<V4*/3])4T\M,C`R,BU*4#]"/T=Y4D%.144W
M96E23U!Y:S=D"FAS;U-G/3T_/2`]/TE33RTR,`HR,BU*4#]"/T=Y4D%.144W
M96E23U!Y:S=D:'-O4V<]/3\]"CT_25-/+3(P,C(M2E`_0C]'>5)!3D5%-V5I
44D]*55EL3QM;2U-624=Y:$L_/0H_
eofeof

$example['mime.ans.strict'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M/3])4T\M,C`R,BU*4#]"/T=Y4D%.144W96E23U!Y:S=D"FAS;U-G/3T_/2`]
M/TE33RTR,`HR,BU*4#]"/T=Y4D%.144W96E23U!Y:S=D:'-O4V<]/3\]"CT_
L25-/+3(P,C(M2E`_0C]'>5)!3D5%-V5I4D]*55EL3QM;2U-624=Y:$L_/0H_
eofeof

$example['mime.unbuf.strict'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M&R1"-$$[>B1./RD;*$)H<V]39ST]/ST@/3])4T\M,C`*,C(M2E`_0C]'>5)!
M3D5%-V5I4D]0>6LW9&AS;U-G/3T_/0H;)$(T03MZ)$XE1ALH0EM+4U9)1WEH
$2S\]"F5I
eofeof

$example['mime.ans'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M&R1"-$$[>B1./RD;*$)H<V]39ST]/ST@&R1"-$$[>B1./RD[=ALH0@H;)$(T
603MZ)$XE1ALH0EM+4U9)1WEH2S\]"@`*
eofeof

$example['mime.unbuf'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M&R1"-$$[>B1./RD;*$)H<V]39ST]/ST@&R1"-$$[>B1./RD[=ALH0@H;)$(T
603MZ)$XE1ALH0EM+4U9)1WEH2S\]"@`*
eofeof

$example['mime.base64'] = <<'eofeof'.unpack('u')[0]
M9W-M5"])3&YG<FU#>$I+-&=Q=4,S24LS9W%Q0E%:3TUI-39,,S0Q-&=S5T)1
M43!+9VUA1%9O3T@*9S)+1%1O3'=K8C)1;$E+;V=Q2T-X24MG9W5M0W%*3EEG
<<T=#>$E+9V=U;4,X64Q&9W)70S592VMG<6U""F=Q
eofeof

$example['mime.base64.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$M&?B1I)#LD1D0Z)"TD7B0Y)"PA(D5L-7XV83E9)$<A(ALH0@T*&R1"
M(T<E-R5G)4,E+R1R0C\_="0J)"0D1B0B)&LD*D4Y)$,D1B0B)&LD<R1')#<D
(9R0F)"L;*$(E
eofeof

# print "Next test is expected to Fail.\n";
print "MIME decode (strict)   ";
    $tmp = test("-j -mS",$example['mime.iso2022'],[$example['mime.ans.strict']])

$example['mime.ans.alt'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"96YD"ALD0B0])"8D*R1*&RA"&R1"-$$[>B1./RD[=ALH0F5N9&]F;&EN
M90H;)$(T03MZ)$X_*3MV-$$[>B1./RD[=ALH0@I"<F]K96YC87-E"ALD0C1!
H.WHD3C\I.W8T03MZ)$X_*3MV&RA""ALD0C1!.WHD3B5&)3DE)!LH0@``
eofeof

$example['mime.unbuf.alt'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"96YD"ALD0B0])"8D*R1*&RA"&R1"-$$[>B1./RD[=ALH0F5N9&]F;&EN
M90H;)$(T03MZ)$X_*3MV-$$[>B1./RD[=ALH0@I"<F]K96YC87-E"ALD0C1!
H.WHD3C\I.W8T03MZ)$X_*3MV&RA""ALD0C1!.WHD3B5&)3DE)!LH0@``
eofeof

print "MIME decode (nonstrict)";
    $tmp = test("-j -mN",$example['mime.iso2022'],[$example['mime.ans'],$example['mime.ans.alt']])
    # open(OUT,">tmp1");print OUT pack('u',$tmp);close(OUT);
# unbuf mode implies more pessimistic decode
print "MIME decode (unbuf)    ";
    $tmp = test("-j -mNu",$example['mime.iso2022'],[$example['mime.unbuf'],$example['mime.unbuf.alt']])
    # open(OUT,">tmp2");print OUT pack('u',$tmp);close(OUT);
print "MIME decode (base64)   ";
    test("-j -mB",$example['mime.base64'],[$example['mime.base64.ans']])

# MIME ISO-8859-1

$example['mime.is8859'] = <<'eofeof'.unpack('u')[0]
M/3])4T\M.#@U.2TQ/U$_*CU#-V%V83\_/2`*4&5E<B!4]G)N9W)E;@I,87-S
M92!(:6QL97+X92!0971E<G-E;B`@7"`B36EN(&MA97!H97-T(&AA<B!F86%E
M="!E="!F;V5L(2(*06%R:'5S(%5N:79E<G-I='DL($1%3DU!4DL@(%P@(DUI
<;B!KYG!H97-T(&AA<B!FY65T(&5T(&;X;"$B"@!K
eofeof

$example['mime.is8859.ans'] = <<'eofeof'.unpack('u')[0]
M*L=A=F$_(`I0965R(%3V<FYG<F5N"DQA<W-E($AI;&QE<OAE(%!E=&5R<V5N
M("!<(")-:6X@:V%E<&AE<W0@:&%R(&9A865T(&5T(&9O96PA(@I!87)H=7,@
M56YI=F5R<VET>2P@1$5.34%22R`@7"`B36EN(&OF<&AE<W0@:&%R(&;E970@
)970@9OAL(2(*
eofeof

# Without -l, ISO-8859-1 was handled as X0201.

print "MIME ISO-8859-1 (Q)    ";
    test("-ml",$example['mime.is8859'],[$example['mime.is8859.ans']])

# test for -f is not so simple.

print "\nBug Fixes\n\n";

# test_data/cr

$example['test_data/cr'] = <<'eofeof'.unpack('u')[0]
1I,:DN:3(#71E<W0-=&5S=`T`
eofeof

$example['test_data/cr.ans'] = <<'eofeof'.unpack('u')[0]
7&R1")$8D.21(&RA""G1E<W0*=&5S=`H`
eofeof

print "test_data/cr    ";
    test("-jd",$example['test_data/cr'],[$example['test_data/cr.ans']])
# test_data/fixed-qencode

$example['test_data/fixed-qencode'] = <<'eofeof'.unpack('u')[0]
M("`@("`@("`],4(D0CYE/STS1#TQ0BA""B`@("`@("`@/3%")$(^93TS1CTS
'1#TQ0BA""@``
eofeof

$example['test_data/fixed-qencode.ans'] = <<'eofeof'.unpack('u')[0]
F("`@("`@("`;)$(^93\]&RA""B`@("`@("`@&R1"/F4_/1LH0@H`
eofeof

print "test_data/fixed-qencode    ";
    test("-jmQ",$example['test_data/fixed-qencode'],[$example['test_data/fixed-qencode.ans']])
# test_data/long-fold-1

$example['test_data/long-fold-1'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AHJ2SI.RD
M\J2]I,ZDWJ3>I**DQ*2KI*:DR*&BI,FDIJ3BI-^DT*2HI*RD[Z3KI*2DMZ&B
MI,BDP:3EI*:DQZ3!I.>D\Z2NI.RDZZ2KI.*DMZ3SI,JDI*&C"J2SI+.DSR!#
M4B],1B"DSKG4H:,-"J2SI+.DSR!#4B"DSKG4H:,-I+.DLZ3/($Q&+T-2(*3.
9N=2AHPH-"J2SI+.DSR!,1B"DSKG4H:,*"@``
eofeof

$example['test_data/long-fold-1.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$HD+"0D)$HD+"0D)$HD+"%!)"0D+B1G)"8D+"0B)&HD7B0W)$8A(B0S
M)&PD<B0])$XD7B1>)"(D1"0K&RA""ALD0B0F)$@A(B1))"8D8B1?)%`D*"0L
M)&\D:R0D)#<A(B1()$$D920F)$<D021G)',D+B1L)&LD*R1B)#<D<QLH0@H;
M)$(D2B0D(2,;*$(*&R1")#,D,R1/&RA"($-2+TQ&(!LD0B1..50A(QLH0@H;
M)$(D,R0S)$\;*$(@0U(@&R1")$XY5"$C&RA""ALD0B0S)#,D3QLH0B!,1B]#
M4B`;)$(D3CE4(2,;*$(*"ALD0B0S)#,D3QLH0B!,1B`;)$(D3CE4(2,;*$(*
!"@``
eofeof

print "test_data/long-fold-1    ";
    test("-jF60",$example['test_data/long-fold-1'],[$example['test_data/long-fold-1.ans']])
# test_data/long-fold

$example['test_data/long-fold'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AHJ2SI.RD
M\J2]I,ZDWJ3>I**DQ*2KI*:DR*&BI,FDIJ3BI-^DT*2HI*RD[Z3KI*2DMZ&B
MI,BDP:3EI*:DQZ3!I.>D\Z2NI.RDZZ2KI.*DMZ3SI,JDI*&C"J2SI+.DS\.[
'I*2YU*&C"@``
eofeof

$example['test_data/long-fold.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$HD+"0D)$HD+"0D)$HD+"%!)"0D+B1G)"8D+"0B)&HD7B0W)$8A(B0S
M)&PD<B0])$XD7B1>)"(D1"0K&RA""ALD0B0F)$@A(B1))"8D8B1?)%`D*"0L
M)&\D:R0D)#<A(B1()$$D920F)$<D021G)',D+B1L)&LD*R1B)#<D<QLH0@H;
:)$(D2B0D(2,D,R0S)$]#.R0D.50A(QLH0@H`
eofeof

print "test_data/long-fold    ";
    test("-jf60",$example['test_data/long-fold'],[$example['test_data/long-fold.ans']])
# test_data/mime_out

$example['test_data/mime_out'] = <<'eofeof'.unpack('u')[0]
M"BTM+2T*4W5B:F5C=#H@86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$@
M86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$@86%A82!A86%A"BTM+2T*
M4W5B:F5C=#H@I**DI*2FI*BDJJ2KI*VDKZ2QI+.DM:2WI+FDNZ2]I+^DP:3$
MI,:DR*3*I,NDS*3-I,ZDSZ32I-6DV*3;I-ZDWZ3@I.&DXJ3DI*2DYJ2HI.@*
M+2TM+0I3=6)J96-T.B!A86%A(&%A86$@86%A82!A86%A(&%A86$@86%A82!A
I86%A(*2BI*2DIJ2HI*H@86%A82!A86%A(&%A86$@86%A80HM+2TM"@H`
eofeof

$example['test_data/mime_out.ans'] = <<'eofeof'.unpack('u')[0]
M"BTM+2T*4W5B:F5C=#H@86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$@
M86%A82!A86%A(&%A86$@86%A80H@86%A82!A86%A(&%A86$@86%A82!A86%A
M"BTM+2T*4W5B:F5C=#H@/3])4T\M,C`R,BU*4#]"/T=Y4D-*0TEK2D-1;4I#
M9VM+:5%R2D,P:TQY47A*1$UK3E-1,T=Y:$,_/0H@/3])4T\M,C`R,BU*4#]"
M/T=Y4D-*1&MK3WE1.4I$.&M14U)%2D59:U-#4DM*17-K5$-23DI%-&M4>5)3
M2D95:U=#4F)'>6A#/ST*(#T_25-/+3(P,C(M2E`_0C]'>5)#2D8T:UAY4F=*
M1T5K66E2:TI#46M::5%O2D=G8DM%23T_/0HM+2TM"E-U8FIE8W0Z(&%A86$@
M86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$*(#T_25-/+3(P,C(M2E`_
M0C]'>5)#2D-):TI#46U*0V=K2VAS;U%G/3T_/2!A86%A(&%A86$@86%A82!A
086%A"B!A86%A"BTM+2T*"@``
eofeof

print "test_data/mime_out    ";
    test("-jM",$example['test_data/mime_out'],[$example['test_data/mime_out.ans']])
# test_data/mime_out2

$example['test_data/mime_out2'] = <<'eofeof'.unpack('u')[0]
M5&AI<R!M96UO(&1E<V-R:6)E<R!S:6UI;&%R('1E8VAN:7%U97,@=&\@86QL
M;W<@=&AE(&5N8V]D:6YG(&]F(&YO;BU!4T-)22!T97AT(&EN('9A<FEO=7,@
M<&]R=&EO;G,@;V8@82!21D,@.#(R(%LR72!M97-S86=E(&AE861E<BP@:6X@
M82!M86YN97(@=VAI8V@@:7,@=6YL:6ME;'D@=&\@8V]N9G5S92!E>&ES=&EN
M9R!M97-S86=E(&AA;F1L:6YG('-O9G1W87)E+@H*4W5B:F5C=#H@=&5S=#$@
M=&5S=#(@@L2"MX+&@J<@=&5S=#,@@L2"MX+&@O$@=&5S=#0*"E-U8FIE8W0Z
M('1E<W0Q("!T97-T,B""Q"""MR""QB""IR!T97-T,R`@@L2"MX+&@O$@('1E
M<W0T"@I!4T-)22"3^I9[C.H@05-#24D@05-#24D@D_J6>XSJ()/ZEGN,ZB!!
M4T-)22!!4T-)29/ZEGN,ZB!!4T-)20H*@J`@@J(@@J0@@J8@@J@@@JD@@JL@
M@JT@@J\@@K$@@K,@@K4@@K<@@KD@@KL@@KT@@K\@@L(@@L0@@L8@@L@@@LD@
8@LH@@LL@@LP*"@H*"@H*"@H*"@H*"@H*
eofeof

$example['test_data/mime_out2.ans'] = <<'eofeof'.unpack('u')[0]
M5&AI<R!M96UO(&1E<V-R:6)E<R!S:6UI;&%R('1E8VAN:7%U97,@=&\@86QL
M;W<@=&AE(&5N8V]D:6YG(&5N8V]D:6YG"B!O9B!N;VXM05-#24D@=&5X="!I
M;B!V87)I;W5S('!O<G1I;VYS(&]F(&$@80H@4D9#(#@R,B!;,ET@;65S<V%G
M92!H96%D97(L(&EN(&$@;6%N;F5R('=H:6-H(&ES('5N;&EK96QY('5N;&EK
M96QY"B!T;R!C;VYF=7-E(&5X:7-T:6YG(&UE<W-A9V4@:&%N9&QI;F<@<V]F
M='=A<F4N"@I3=6)J96-T.B!T97-T,2!T97-T,B`]/TE33RTR,#(R+4I0/T(_
M1WE20TI%66M/4U))2D-K8DM%23T_/2!T97-T,PH@/3])4T\M,C`R,BU*4#]"
M/T=Y4D-*15EK3U-224I(36)+14D]/ST@=&5S=#0*"E-U8FIE8W0Z('1E<W0Q
M("!T97-T,B`]/TE33RTR,#(R+4I0/T(_1WE20TI%66)+14EG1WE20TI$:V)+
M14EG1WE20TI%9V)+14D]/ST*(#T_25-/+3(P,C(M2E`_0C]'>5)#1WEH0TE"
M<VM1:5%P1WEH0S\]('1E<W0S(`H@/3])4T\M,C`R,BU*4#]"/T=Y4D-*15EK
M3U-224I(36)+14D]/ST@('1E<W0T"@I!4T-)22`]/TE33RTR,#(R+4I0/T(_
M1WE20U)N>$Q81&AS1WEH0S\]($%30TE)($%30TE)"B`]/TE33RTR,#(R+4I0
M/T(_1WE20U)N>$Q81&AS1WEH0TE"<VM1:UHX4S%W-&)"<V]19ST]/ST@05-#
M24D*(#T_25-/+3(P,C(M2E`_0C]15DY$4U5K8DI%2D=F171C3T=W8DM%23T_
M/2!!4T-)20H*/3])4T\M,C`R,BU*4#]"/T=Y4D-*0TEB2T5)9T=Y4D-*0U%B
M2T5)9T=Y4D-*0UEB2T5)9T=Y4D-*0V=B2T5)/3\]"B`]/TE33RTR,#(R+4I0
M/T(_24)S:U%I47%'>6A#24)S:U%I47)'>6A#24)S:U%I471'>6A#24)S:U%I
M479'>6A#/ST*(#T_25-/+3(P,C(M2E`_0C])0G-K46E1>$=Y:$-)0G-K46E1
M>D=Y:$-)0G-K46E1,4=Y:$-)0G-K46E1,T=Y:$,_/0H@/3])4T\M,C`R,BU*
M4#]"/TE"<VM1:5$U1WEH0TE"<VM1:5$W1WEH0TE"<VM1:5$Y1WEH0TE"<VM1
M:5$O1WEH0S\]"B`]/TE33RTR,#(R+4I0/T(_24)S:U%I4D)'>6A#24)S:U%I
M4D5'>6A#24)S:U%I4D='>6A#24)S:U%I4DE'>6A#/ST*(#T_25-/+3(P,C(M
M2E`_0C])0G-K46E22T=Y:$-)0G-K46E23$=Y:$-)0G-K46E234=Y:$-)0G-K
M46E23D=Y:$,_/0H@/3])4T\M,C`R,BU*4#]"/TE"<VM1:5)/1WEH0S\]"@H*
-"@H*"@H*"@H*"@H*"@``
eofeof

print "test_data/mime_out2    ";
    test("-jM",$example['test_data/mime_out2'],[$example['test_data/mime_out2.ans']])
# test_data/multi-line

$example['test_data/multi-line'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AH@"DLZ3L
MI/*DO:3.I-ZDWJ2BI,2DJZ2FI,BAHJ3)I*:DXJ3?I-"DJ*2LI.^DZZ2DI+>A
MHJ3(I,&DY:2FI,>DP:3GI/.DKJ3LI.NDJZ3BI+>D\Z3*I*2AHPJDLZ2SI,_#
8NZ2DN=2AHP`*I+.DLZ3/P[NDI+G4H:,*
eofeof

$example['test_data/multi-line.ans'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AH@"DLZ3L
MI/*DO:3.I-ZDWJ2BI,2DJZ2FI,BAHJ3)I*:DXJ3?I-"DJ*2LI.^DZZ2DI+>A
MHJ3(I,&DY:2FI,>DP:3GI/.DKJ3LI.NDJZ3BI+>D\Z3*I*2AHPJDLZ2SI,_#
8NZ2DN=2AHP`*I+.DLZ3/P[NDI+G4H:,*
eofeof

print "test_data/multi-line    ";
    test("-e",$example['test_data/multi-line'],[$example['test_data/multi-line.ans']])
# test_data/nkf-19-bug-1

$example['test_data/nkf-19-bug-1'] = <<'eofeof'.unpack('u')[0]
,I*:DJZ2D"KK8QJ,*
eofeof

$example['test_data/nkf-19-bug-1.ans'] = <<'eofeof'.unpack('u')[0]
8&R1")"8D*R0D&RA""ALD0CI81B,;*$(*
eofeof

print "test_data/nkf-19-bug-1    ";
    test("-Ej",$example['test_data/nkf-19-bug-1'],[$example['test_data/nkf-19-bug-1.ans']])
# test_data/nkf-19-bug-2

$example['test_data/nkf-19-bug-2'] = <<'eofeof'.unpack('u')[0]
%I-NDL@H`
eofeof

$example['test_data/nkf-19-bug-2.ans'] = <<'eofeof'.unpack('u')[0]
%I-NDL@H`
eofeof

print "test_data/nkf-19-bug-2    ";
    test("-Ee",$example['test_data/nkf-19-bug-2'],[$example['test_data/nkf-19-bug-2.ans']])
# test_data/nkf-19-bug-3

$example['test_data/nkf-19-bug-3'] = <<'eofeof'.unpack('u')[0]
8[;'Q\,&L"N6ZSN\*\NT)ON7.SL_+"0D*
eofeof

$example['test_data/nkf-19-bug-3.ans'] = <<'eofeof'.unpack('u')[0]
8[;'Q\,&L"N6ZSN\*\NT)ON7.SL_+"0D*
eofeof

print "test_data/nkf-19-bug-3    ";
    test("-e",$example['test_data/nkf-19-bug-3'],[$example['test_data/nkf-19-bug-3.ans']])
# test_data/non-strict-mime

$example['test_data/non-strict-mime'] = <<'eofeof'.unpack('u')[0]
M/3])4T\M,C`R,BU*4#]"/PIG<U-#;V]+.6=R-D-O;TQ%9W1Y0W0T1D-$46].
M0V\V16=S,D]N;T999S1Y1%=)3$IG=4-0:UD*2W!G<FU#>$E+:6=R,D-V;TMI
,9W-30V]O3&,*/ST*
eofeof

$example['test_data/non-strict-mime.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$8D)"0_)$`D)"1&)%XD.2$C&RA"#0H-"ALD0CMD)$\[?B$Y)6PE.21+
<)&(]<20K)#LD1B0D)#\D0"0D)$8D)"1>&RA""@``
eofeof

print "test_data/non-strict-mime    ";
    test("-jmN",$example['test_data/non-strict-mime'],[$example['test_data/non-strict-mime.ans']])
# test_data/q-encode-softrap

$example['test_data/q-encode-softrap'] = <<'eofeof'.unpack('u')[0]
H/3%")$(T03MZ)3T*,R$\)4DD3CTQ0BA""CTQ0B1"2E$T.3TQ0BA""@``
eofeof

$example['test_data/q-encode-softrap.ans'] = <<'eofeof'.unpack('u')[0]
>&R1"-$$[>B4S(3PE221.&RA""ALD0DI1-#D;*$(*
eofeof

print "test_data/q-encode-softrap    ";
    test("-jmQ",$example['test_data/q-encode-softrap'],[$example['test_data/q-encode-softrap.ans']])
# test_data/rot13

$example['test_data/rot13'] = <<'eofeof'.unpack('u')[0]
MI+.D\Z3+I,&DSZ&BS:W"]*3(I*2DI*3>I+FAHPH*;FMF('9E<BXQ+CDR(*3R
MS?C-T:2UI+NDQJ2DI+^DP*2DI,:DI*3>I+FDK*&B05-#24D@I,O"T*2WI,8@
M4D]4,3,@I*P*P+6DMZ2OQK"DI*3&I*2DRJ2DI.BDIJ3'H:*PRK*\I,ZDZ*2F
MI,O*T;2YI+6D[*3>I+ND\Z&C"@HE(&5C:&\@)VAO9V4G('P@;FMF("UR"FAO
#9V4*
eofeof

$example['test_data/rot13.ans'] = <<'eofeof'.unpack('u')[0]
M&R1"4V)31%-Z4W!3?E!1?%QQ15-W4U-34U,O4VA04ALH0@H*87AS(&ER92XQ
M+CDR(!LD0E-#?$E\(E-D4VI3=5-34VY3;U-34W534U,O4VA36U!1&RA"3D90
M5E8@&R1"4WIQ(5-F4W4;*$(@14)',3,@&R1"4UL;*$(*&R1";V139E->=5]3
M4U-U4U-3>5-34SE355-V4%%?>6%K4WU3.5-54WIY(F-H4V13/5,O4VI31%!2
A&RA""@HE(')P=6(@)W5B='(G('P@87AS("UE"G5B='(*
eofeof

print "test_data/rot13    ";
    test("-jr",$example['test_data/rot13'],[$example['test_data/rot13.ans']])
# test_data/slash

$example['test_data/slash'] = <<'eofeof'.unpack('u')[0]
7("`]/U8\5"U5.5=%2RTK.U<U32LE+PH`
eofeof

$example['test_data/slash.ans'] = <<'eofeof'.unpack('u')[0]
7("`]/U8\5"U5.5=%2RTK.U<U32LE+PH`
eofeof

print "test_data/slash    ";
    test(" ",$example['test_data/slash'],[$example['test_data/slash.ans']])
# test_data/z1space-0

$example['test_data/z1space-0'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

$example['test_data/z1space-0.ans'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

print "test_data/z1space-0    ";
    test("-e -Z",$example['test_data/z1space-0'],[$example['test_data/z1space-0.ans']])
# test_data/z1space-1

$example['test_data/z1space-1'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

$example['test_data/z1space-1.ans'] = <<'eofeof'.unpack('u')[0]
!(```
eofeof

print "test_data/z1space-1    ";
    test("-e -Z1",$example['test_data/z1space-1'],[$example['test_data/z1space-1.ans']])
# test_data/z1space-2

$example['test_data/z1space-2'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

$example['test_data/z1space-2.ans'] = <<'eofeof'.unpack('u')[0]
"("``
eofeof

print "test_data/z1space-2    ";
    test("-e -Z2",$example['test_data/z1space-2'],[$example['test_data/z1space-2.ans']])


# end
