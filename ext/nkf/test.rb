#!/usr/local/bin/ruby
#
# nkf test program for nkf 1.7
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
  print "\nGOT:\n", result if $detail

  expects.each do |e|
    if result == e then
      puts "Ok"
      return result
    end
  end
  puts "Fail"
end


example = Hash.new

# Basic Conversion
print "\nBasic Conversion test\n\n";

# I gave up simple literal quote because there are big difference
# on perl4 and perl5 on literal quote. Of course we cannot use
# jperl.

example['jis'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@&R1"(3DQ(3%^2R%+?D]3&RA"(%-E8V]N9"!3=&%G92`;
M)$)0)TU:&RA"($AI<F%G86YA(!LD0B0B)"0D)B0H)"HD;R1R)',;*$(*2V%T
M86MA;F$@&R1")2(E)"4F)2@E*B5O)7(E<QLH0B!+:6=O=2`;)$(A)B%G(S`C
/029!)E@G(B=!*$`;*$(*
eofeof

example['sjis'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@@5B)0(F>ED"6GIAR(%-E8V]N9"!3=&%G92"8I9=Y($AI
M<F%G86YA((*@@J*"I(*F@JB"[8+P@O$*2V%T86MA;F$@@T&#0X-%@T>#28./
>@Y*#DR!+:6=O=2"!18&'@D^"8(._@]:$081@A+X*
eofeof

example['euc'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@H;FQH;'^RZ'+_L_3(%-E8V]N9"!3=&%G92#0I\W:($AI
M<F%G86YA(*2BI*2DIJ2HI*JD[Z3RI/,*2V%T86MA;F$@I:*EI*6FI:BEJJ7O
>I?*E\R!+:6=O=2"AIJ'GH["CP:;!IMBGHJ?!J,`*
eofeof

example['utf'] = <<'eofeof'.unpack('u')[0]
M1FER<W0@4W1A9V4@XX"%Z9FBY;^<YK.5YKJ`Z(65(%-E8V]N9"!3=&%G92#D
MN+SI@:4@2&ER86=A;F$@XX&"XX&$XX&&XX&(XX&*XX*/XX*2XX*3"DMA=&%K
M86YA(.."HN."I.."IN."J.."JN.#K^.#LN.#LR!+:6=O=2#C@[OBB)[OO)#O
.O*'.L<^)T)'0K^*5@@H`
eofeof


example['jis1'] = <<'eofeof'.unpack('u')[0]
M&R1";3%Q<$$L&RA""ALD0F4Z3F\;*$(*&R1"<FT;*$()&R1"/F5.3D]+&RA"
#"0D*
eofeof

example['sjis1'] = <<'eofeof'.unpack('u')[0]
8YU#ID)%+"N-9E^T*Z>L)C^.7S)AJ"0D*
eofeof

example['euc1'] = <<'eofeof'.unpack('u')[0]
8[;'Q\,&L"N6ZSN\*\NT)ON7.SL_+"0D*
eofeof

example['utf1'] = <<'eofeof'.unpack('u')[0]
AZ+J%Z:N/Z8JM"N>VNNFZEPKIM(D)Y+B*Z:"8Y+J8"0D*
eofeof

example['jis2'] = <<'eofeof'.unpack('u')[0]
+&R1".EA&(QLH0@H`
eofeof

example['sjis2'] = <<'eofeof'.unpack('u')[0]
%C=:3H0H`
eofeof

example['euc2'] = <<'eofeof'.unpack('u')[0]
%NMC&HPH`
eofeof

example['utf2'] = <<'eofeof'.unpack('u')[0]
'YI:.Z)>D"@``
eofeof

# From JIS

print "JIS  to JIS ... ";test('-j',example['jis'],[example['jis']]);
print "JIS  to SJIS... ";test('-s',example['jis'],[example['sjis']]);
print "JIS  to EUC ... ";test('-e',example['jis'],[example['euc']]);
print "JIS  to UTF8... ";test('-w',example['jis'],[example['utf']]);

# From SJIS

print "SJIS to JIS ... ";test('-j',example['sjis'],[example['jis']]);
print "SJIS to SJIS... ";test('-s',example['sjis'],[example['sjis']]);
print "SJIS to EUC ... ";test('-e',example['sjis'],[example['euc']]);
print "SJIS to UTF8... ";test('-w',example['sjis'],[example['utf']]);

# From EUC

print "EUC  to JIS ... ";test('-j',example['euc'],[example['jis']]);
print "EUC  to SJIS... ";test('-s',example['euc'],[example['sjis']]);
print "EUC  to EUC ... ";test('-e',example['euc'],[example['euc']]);
print "EUC  to UTF8... ";test('-w',example['euc'],[example['utf']]);

# From UTF8

print "UTF8 to JIS ... ";test('-j',example['utf'],[example['jis']]);
print "UTF8 to SJIS... ";test('-s',example['utf'],[example['sjis']]);
print "UTF8 to EUC ... ";test('-e',example['utf'],[example['euc']]);
print "UTF8 to UTF8... ";test('-w',example['utf'],[example['utf']]);



# From JIS

print "JIS  to JIS ... ";test('-j',example['jis1'],[example['jis1']]);
print "JIS  to SJIS... ";test('-s',example['jis1'],[example['sjis1']]);
print "JIS  to EUC ... ";test('-e',example['jis1'],[example['euc1']]);
print "JIS  to UTF8... ";test('-w',example['jis1'],[example['utf1']]);

# From SJIS

print "SJIS to JIS ... ";test('-j',example['sjis1'],[example['jis1']]);
print "SJIS to SJIS... ";test('-s',example['sjis1'],[example['sjis1']]);
print "SJIS to EUC ... ";test('-e',example['sjis1'],[example['euc1']]);
print "SJIS to UTF8... ";test('-w',example['sjis1'],[example['utf1']]);

# From EUC

print "EUC  to JIS ... ";test('-j',example['euc1'],[example['jis1']]);
print "EUC  to SJIS... ";test('-s',example['euc1'],[example['sjis1']]);
print "EUC  to EUC ... ";test('-e',example['euc1'],[example['euc1']]);
print "EUC  to UTF8... ";test('-w',example['euc1'],[example['utf1']]);

# From UTF8

print "UTF8 to JIS ... ";test('-j',example['utf1'],[example['jis1']]);
print "UTF8 to SJIS... ";test('-s',example['utf1'],[example['sjis1']]);
print "UTF8 to EUC ... ";test('-e',example['utf1'],[example['euc1']]);
print "UTF8 to UTF8... ";test('-w',example['utf1'],[example['utf1']]);

# Ambigous Case

example['amb'] = <<'eofeof'.unpack('u')[0]
MI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&E
MPK"QI<*PL:7"L+&EPK"QI<(*I<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*P
ML:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<(*I<*PL:7"L+&E
MPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"
ML+&EPK"QI<(*I<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"Q
MI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<(*I<*PL:7"L+&EPK"QI<*PL:7"
ML+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<*PL:7"L+&EPK"QI<(*
eofeof

example['amb.euc'] = <<'eofeof'.unpack('u')[0]
M&R1")4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25"
M,#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*&R1")4(P,25",#$E0C`Q)4(P,25"
M,#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;
M*$(*&R1")4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P
M,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*&R1")4(P,25",#$E0C`Q)4(P
M,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q
M)4(;*$(*&R1")4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q
>)4(P,25",#$E0C`Q)4(P,25",#$E0C`Q)4(;*$(*
eofeof

example['amb.sjis'] = <<'eofeof'.unpack('u')[0]
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
    test('-j',example['amb'],[example['amb.euc']]);

# Input assumption

print "SJIS  Input assumption ";
    test('-jSx',example['amb'],[example['amb.sjis']]);

# Broken JIS

print "Broken JIS ";
    $input = example['jis'];
    $input.gsub("\033",'');
    test('-Be',$input,[example['euc']]);
print "Broken JIS is safe on Normal JIS? ";
    $input = example['jis'];
    test('-Be',$input,[example['euc']]);

# X0201 仮名
# X0201->X0208 conversion
# X0208 aphabet -> ASCII
# X0201 相互変換

print "\nX0201 test\n\n";

example['x0201.sjis'] = <<'eofeof'.unpack('u')[0]
MD5.*<(-*@TR#3H-0@U*#2X--@T^#48-3"I%3B7""8()A@F*"8X)D@F6"9H*!
M@H*"@X*$@H6"AH*'"I%3BTR-AH%)@9>!E(&0@9.!3X&5@9:!:8%J@7R!>X&!
M@6V!;H%O@7"!CPJ4O(IPMK>X/;FZMMZWWKC>N=ZZWH+&"I2\BG#*W\O?S-_-
MW\[?M]^QW@K*W\O?S`IH86YK86MU(,K?R]_,I`K*W\O?S-VA"I2\BG""S(SC
!"@!"
eofeof

example['x0201.euc'] = <<'eofeof'.unpack('u')[0]
MP;2ST:6KI:VEKZ6QI;.EK*6NI;"ELJ6T"L&TL=&CP:/"H\.CQ*/%H\:CQZ/A
MH^*CXZ/DH^6CYJ/G"L&TM:VYYJ&JH?>A]*'PH?.AL*'UH?:ARJ'+H=VAW*'A
MH<ZASZ'0H=&A[PK(OK/1CK:.MXZX/8ZYCKJ.MH[>CK>.WHZXCMZ.N8[>CKJ.
MWJ3("LB^L]&.RH[?CLN.WX[,CM^.S8[?CLZ.WXZWCM^.L8[>"H[*CM^.RX[?
MCLP*:&%N:V%K=2".RH[?CLN.WX[,CJ0*CLJ.WX[+CM^.S([=CJ$*R+ZST:3.
#N.4*
eofeof

example['x0201.utf'] = <<'eofeof'.unpack('u')[0]
MY86HZ*>2XX*KXX*MXX*OXX*QXX*SXX*LXX*NXX*PXX*RXX*T"N6%J.B+L>^\
MH>^\HN^\H^^\I.^\I>^\IN^\I^^]@>^]@N^]@^^]A.^]A>^]AN^]APKEA:CH
MJ)CEC[?OO('OO*#OO(/OO(3OO(7OO+[OO(;OO(KOO(COO(GBB)+OO(OOO)WO
MO+OOO+WOO9OOO9WOOZ4*Y8V*Z*>2[[VV[[VW[[VX/>^]N>^]NN^]MN^^GN^]
MM^^^GN^]N.^^GN^]N>^^GN^]NN^^GN.!J`KEC8KHIY+OOHKOOI_OOHOOOI_O
MOHSOOI_OOHWOOI_OOH[OOI_OO;?OOI_OO;'OOIX*[[Z*[[Z?[[Z+[[Z?[[Z,
M"FAA;FMA:W4@[[Z*[[Z?[[Z+[[Z?[[Z,[[VD"N^^BN^^G^^^B^^^G^^^C.^^
2G>^]H0KEC8KHIY+C@:[EOHP*
eofeof

example['x0201.jis'] = <<'eofeof'.unpack('u')[0]
M&R1"030S424K)2TE+R4Q)3,E+"4N)3`E,B4T&RA""ALD0D$T,5$C02-"(T,C
M1"-%(T8C1R-A(V(C8R-D(V4C9B-G&RA""ALD0D$T-2TY9B$J(7<A="%P(7,A
M,"%U(78A2B%+(5TA7"%A(4XA3R%0(5$A;QLH0@H;)$)(/C-1&RA)-C<X&RA"
M/1LH23DZ-EXW7CA>.5XZ7ALD0B1(&RA""ALD0D@^,U$;*$E*7TM?3%]-7TY?
M-U\Q7ALH0@H;*$E*7TM?3!LH0@IH86YK86MU(!LH24I?2U],)!LH0@H;*$E*
97TM?3%TA&RA""ALD0D@^,U$D3CAE&RA""@``
eofeof

example['x0201.sosi'] = <<'eofeof'.unpack('u')[0]
M&R1"030S424K)2TE+R4Q)3,E+"4N)3`E,B4T&RA*"ALD0D$T,5$C02-"(T,C
M1"-%(T8C1R-A(V(C8R-D(V4C9B-G&RA*"ALD0D$T-2TY9B$J(7<A="%P(7,A
M,"%U(78A2B%+(5TA7"%A(4XA3R%0(5$A;QLH2@H;)$)(/C-1&RA*#C8W.`\;
M*$H]#CDZ-EXW7CA>.5XZ7@\;)$(D2!LH2@H;)$)(/C-1&RA*#DI?2U],7TU?
M3E\W7S%>#PH.2E]+7TP/&RA*"FAA;FMA:W4@#DI?2U],)`\;*$H*#DI?2U],
672$/&RA*"ALD0D@^,U$D3CAE&RA""@``
eofeof

example['x0201.x0208'] = <<'eofeof'.unpack('u')[0]
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
    test('-jXZ',example['x0201.sjis'],[example['x0201.x0208']]);
print "X0201 conversion: JIS  ";
    test('-jZ',example['x0201.jis'],[example['x0201.x0208']]);
print "X0201 conversion:SI/SO ";
    test('-jZ',example['x0201.sosi'],[example['x0201.x0208']]);
print "X0201 conversion: EUC  ";
    test('-jZ',example['x0201.euc'],[example['x0201.x0208']]);
print "X0201 conversion: UTF8 ";
    test('-jZ',example['x0201.utf'],[example['x0201.x0208']]);
# -x means X0201 output
print "X0201 output: SJIS     ";
    test('-xs',example['x0201.euc'],[example['x0201.sjis']]);
print "X0201 output: JIS      ";
    test('-xj',example['x0201.sjis'],[example['x0201.jis']]);
print "X0201 output: EUC      ";
    test('-xe',example['x0201.jis'],[example['x0201.euc']]);
print "X0201 output: UTF8     ";
    test('-xw',example['x0201.jis'],[example['x0201.utf']]);

# MIME decode

print "\nMIME test\n\n";

# MIME ISO-2022-JP

example['mime.iso2022'] = <<'eofeof'.unpack('u')[0]
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

example['mime.ans.strict'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M/3])4T\M,C`R,BU*4#]"/T=Y4D%.144W96E23U!Y:S=D"FAS;U-G/3T_/2`]
M/TE33RTR,`HR,BU*4#]"/T=Y4D%.144W96E23U!Y:S=D:'-O4V<]/3\]"CT_
L25-/+3(P,C(M2E`_0C]'>5)!3D5%-V5I4D]*55EL3QM;2U-624=Y:$L_/0H_
eofeof

example['mime.unbuf.strict'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M&R1"-$$[>B1./RD;*$)H<V]39ST]/ST@/3])4T\M,C`*,C(M2E`_0C]'>5)!
M3D5%-V5I4D]0>6LW9&AS;U-G/3T_/0H;)$(T03MZ)$XE1ALH0EM+4U9)1WEH
$2S\]"F5I
eofeof

example['mime.ans'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M&R1"-$$[>B1./RD;*$)H<V]39ST]/ST@&R1"-$$[>B1./RD[=ALH0@H;)$(T
603MZ)$XE1ALH0EM+4U9)1WEH2S\]"@`*
eofeof

example['mime.unbuf'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"(&5N9`H;)$(D/20F)"LD2ALH0B`;)$(T03MZ)$X_*3MV&RA"96YD(&]F
M(&QI;F4*&R1"-$$[>B1./RD[=C1!.WHD3C\I.W8;*$(*0G)O:V5N(&-A<V4*
M&R1"-$$[>B1./RD;*$)H<V]39ST]/ST@&R1"-$$[>B1./RD[=ALH0@H;)$(T
603MZ)$XE1ALH0EM+4U9)1WEH2S\]"@`*
eofeof

example['mime.base64'] = <<'eofeof'.unpack('u')[0]
M9W-M5"])3&YG<FU#>$I+-&=Q=4,S24LS9W%Q0E%:3TUI-39,,S0Q-&=S5T)1
M43!+9VUA1%9O3T@*9S)+1%1O3'=K8C)1;$E+;V=Q2T-X24MG9W5M0W%*3EEG
<<T=#>$E+9V=U;4,X64Q&9W)70S592VMG<6U""F=Q
eofeof

example['mime.base64.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$M&?B1I)#LD1D0Z)"TD7B0Y)"PA(D5L-7XV83E9)$<A(ALH0@T*&R1"
M(T<E-R5G)4,E+R1R0C\_="0J)"0D1B0B)&LD*D4Y)$,D1B0B)&LD<R1')#<D
(9R0F)"L;*$(E
eofeof

# print "Next test is expected to Fail.\n";
print "MIME decode (strict)   ";
    $tmp = test('-jmS',example['mime.iso2022'],[example['mime.ans.strict']]);

example['mime.ans.alt'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"96YD"ALD0B0])"8D*R1*&RA"&R1"-$$[>B1./RD[=ALH0F5N9&]F;&EN
M90H;)$(T03MZ)$X_*3MV-$$[>B1./RD[=ALH0@I"<F]K96YC87-E"ALD0C1!
H.WHD3C\I.W8T03MZ)$X_*3MV&RA""ALD0C1!.WHD3B5&)3DE)!LH0@``
eofeof

example['mime.unbuf.alt'] = <<'eofeof'.unpack('u')[0]
M&R1"-$$[>B1.)48E.25(&RA""ALD0C1!.WHD3B5&)3DE2!LH0@H;)$(D1B11
M&RA"96YD"ALD0B0])"8D*R1*&RA"&R1"-$$[>B1./RD[=ALH0F5N9&]F;&EN
M90H;)$(T03MZ)$X_*3MV-$$[>B1./RD[=ALH0@I"<F]K96YC87-E"ALD0C1!
H.WHD3C\I.W8T03MZ)$X_*3MV&RA""ALD0C1!.WHD3B5&)3DE)!LH0@``
eofeof

print "MIME decode (nonstrict)";
    $tmp = test('-jmN',example['mime.iso2022'],[example['mime.ans'],example['mime.ans.alt']]);
    # open(OUT,">tmp1");print OUT pack('u',$tmp);close(OUT);
# unbuf mode implies more pessimistic decode
print "MIME decode (unbuf)    ";
    $tmp = test('-jmNu',example['mime.iso2022'],[example['mime.unbuf'],example['mime.unbuf.alt']]);
    # open(OUT,">tmp2");print OUT pack('u',$tmp);close(OUT);
print "MIME decode (base64)   ";
    test('-jTmB',example['mime.base64'],[example['mime.base64.ans']]);

# MIME ISO-8859-1

example['mime.is8859'] = <<'eofeof'.unpack('u')[0]
M/3])4T\M.#@U.2TQ/U$_*CU#-V%V83\_/2`*4&5E<B!4]G)N9W)E;@I,87-S
M92!(:6QL97+X92!0971E<G-E;B`@7"`B36EN(&MA97!H97-T(&AA<B!F86%E
M="!E="!F;V5L(2(*06%R:'5S(%5N:79E<G-I='DL($1%3DU!4DL@(%P@(DUI
<;B!KYG!H97-T(&AA<B!FY65T(&5T(&;X;"$B"@!K
eofeof

example['mime.is8859.ans'] = <<'eofeof'.unpack('u')[0]
M*L=A=F$_(`I0965R(%3V<FYG<F5N"DQA<W-E($AI;&QE<OAE(%!E=&5R<V5N
M("!<(")-:6X@:V%E<&AE<W0@:&%R(&9A865T(&5T(&9O96PA(@I!87)H=7,@
M56YI=F5R<VET>2P@1$5.34%22R`@7"`B36EN(&OF<&AE<W0@:&%R(&;E970@
)970@9OAL(2(*
eofeof

# Without -l, ISO-8859-1 was handled as X0201.

print "MIME ISO-8859-1 (Q)    ";
    test('-ml',example['mime.is8859'],[example['mime.is8859.ans']]);

# test for -f is not so simple.

print "\nBug Fixes\n\n";

# test_data/cr

example['test_data/cr'] = <<'eofeof'.unpack('u')[0]
1I,:DN:3(#71E<W0-=&5S=`T`
eofeof

example['test_data/cr.ans'] = <<'eofeof'.unpack('u')[0]
7&R1")$8D.21(&RA""G1E<W0*=&5S=`H`
eofeof

print "test_data/cr    ";
    test('-jd',example['test_data/cr'],[example['test_data/cr.ans']]);
# test_data/fixed-qencode

example['test_data/fixed-qencode'] = <<'eofeof'.unpack('u')[0]
M("`@("`@("`],4(D0CYE/STS1#TQ0BA""B`@("`@("`@/3%")$(^93TS1CTS
'1#TQ0BA""@``
eofeof

example['test_data/fixed-qencode.ans'] = <<'eofeof'.unpack('u')[0]
F("`@("`@("`;)$(^93\]&RA""B`@("`@("`@&R1"/F4_/1LH0@H`
eofeof

print "test_data/fixed-qencode    ";
    test('-jmQ',example['test_data/fixed-qencode'],[example['test_data/fixed-qencode.ans']]);
# test_data/long-fold-1

example['test_data/long-fold-1'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AHJ2SI.RD
M\J2]I,ZDWJ3>I**DQ*2KI*:DR*&BI,FDIJ3BI-^DT*2HI*RD[Z3KI*2DMZ&B
MI,BDP:3EI*:DQZ3!I.>D\Z2NI.RDZZ2KI.*DMZ3SI,JDI*&C"J2SI+.DSR!#
M4B],1B"DSKG4H:,-"J2SI+.DSR!#4B"DSKG4H:,-I+.DLZ3/($Q&+T-2(*3.
9N=2AHPH-"J2SI+.DSR!,1B"DSKG4H:,*"@``
eofeof

example['test_data/long-fold-1.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$HD+"0D)$HD+"0D)$HD+"%!)"0D+B1G)"8D+"0B)&HD7B0W)$8A(B0S
M)&PD<B0])$XD7B1>)"(D1"0K&RA""ALD0B0F)$@A(B1))"8D8B1?)%`D*"0L
M)&\D:R0D)#<A(B1()$$D920F)$<D021G)',D+B1L)&LD*R1B)#<D<QLH0@H;
M)$(D2B0D(2,;*$(*&R1")#,D,R1/&RA"($-2+TQ&(!LD0B1..50A(QLH0@H;
M)$(D,R0S)$\;*$(@0U(@&R1")$XY5"$C&RA""ALD0B0S)#,D3QLH0B!,1B]#
M4B`;)$(D3CE4(2,;*$(*"ALD0B0S)#,D3QLH0B!,1B`;)$(D3CE4(2,;*$(*
!"@``
eofeof

print "test_data/long-fold-1    ";
    test('-jTF60',example['test_data/long-fold-1'],[example['test_data/long-fold-1.ans']]);
# test_data/long-fold

example['test_data/long-fold'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AHJ2SI.RD
M\J2]I,ZDWJ3>I**DQ*2KI*:DR*&BI,FDIJ3BI-^DT*2HI*RD[Z3KI*2DMZ&B
MI,BDP:3EI*:DQZ3!I.>D\Z2NI.RDZZ2KI.*DMZ3SI,JDI*&C"J2SI+.DS\.[
'I*2YU*&C"@``
eofeof

example['test_data/long-fold.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$HD+"0D)$HD+"0D)$HD+"%!)"0D+B1G)"8D+"0B)&HD7B0W)$8A(B0S
M)&PD<B0])$XD7B1>)"(D1"0K&RA""ALD0B0F)$@A(B1))"8D8B1?)%`D*"0L
M)&\D:R0D)#<A(B1()$$D920F)$<D021G)',D+B1L)&LD*R1B)#<D<QLH0@H;
:)$(D2B0D(2,D,R0S)$]#.R0D.50A(QLH0@H`
eofeof

print "test_data/long-fold    ";
    test('-jTf60',example['test_data/long-fold'],[example['test_data/long-fold.ans']]);
# test_data/mime_out

example['test_data/mime_out'] = <<'eofeof'.unpack('u')[0]
M"BTM+2T*4W5B:F5C=#H@86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$@
M86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$@86%A82!A86%A"BTM+2T*
M4W5B:F5C=#H@I**DI*2FI*BDJJ2KI*VDKZ2QI+.DM:2WI+FDNZ2]I+^DP:3$
MI,:DR*3*I,NDS*3-I,ZDSZ32I-6DV*3;I-ZDWZ3@I.&DXJ3DI*2DYJ2HI.@*
M+2TM+0I3=6)J96-T.B!A86%A(&%A86$@86%A82!A86%A(&%A86$@86%A82!A
I86%A(*2BI*2DIJ2HI*H@86%A82!A86%A(&%A86$@86%A80HM+2TM"@H`
eofeof

example['test_data/mime_out.ans'] = <<'eofeof'.unpack('u')[0]
M"BTM+2T*4W5B:F5C=#H@86%A82!A86%A(&%A86$@86%A82!A86%A(&%A86$@
M86%A82!A86%A(&%A86$*(&%A86$@86%A82!A86%A(&%A86$@86%A80HM+2TM
M"E-U8FIE8W0Z(#T_25-/+3(P,C(M2E`_0C]'>5)#2D-):TI#46U*0V=K2VE1
M<DI#,&M,>5%X2D1-:TY343-*1&MK3WAS;U%G/3T_/2`*"3T_25-/+3(P,C(M
M2E`_0C]'>5)#2D0P:U!Y4D)*15%K4FE224I%;VM3>5)-2D4P:U1I4E!*1DEK
M5E-264=Y:$,_/2`*"3T_25-/+3(P,C(M2E`_0C]'>5)#2D9S:UAI4F9*1T%K
M65-2:4I'46M*0U)M2D-G:V%"<V]19ST]/ST@"BTM+2T*4W5B:F5C=#H@86%A
M82!A86%A(&%A86$@86%A82!A86%A(&%A86$@86%A82`]/TE33RTR,#(R+4I0
M/T(_1WE20TI#26)+14D]/ST@"@D]/TE33RTR,#(R+4I0/T(_1WE20TI#46M*
J:5%O2D-O8DM%23T_/2`@86%A80H@86%A82!A86%A(&%A86$*+2TM+0H*
eofeof

print "test_data/mime_out    ";
    test('-jM',example['test_data/mime_out'],[example['test_data/mime_out.ans']]);
# test_data/multi-line

example['test_data/multi-line'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AH@"DLZ3L
MI/*DO:3.I-ZDWJ2BI,2DJZ2FI,BAHJ3)I*:DXJ3?I-"DJ*2LI.^DZZ2DI+>A
MHJ3(I,&DY:2FI,>DP:3GI/.DKJ3LI.NDJZ3BI+>D\Z3*I*2AHPJDLZ2SI,_#
8NZ2DN=2AHP`*I+.DLZ3/P[NDI+G4H:,*
eofeof

example['test_data/multi-line.ans'] = <<'eofeof'.unpack('u')[0]
MI,JDK*2DI,JDK*2DI,JDK*'!I*2DKJ3GI*:DK*2BI.JDWJ2WI,:AH@"DLZ3L
MI/*DO:3.I-ZDWJ2BI,2DJZ2FI,BAHJ3)I*:DXJ3?I-"DJ*2LI.^DZZ2DI+>A
MHJ3(I,&DY:2FI,>DP:3GI/.DKJ3LI.NDJZ3BI+>D\Z3*I*2AHPJDLZ2SI,_#
8NZ2DN=2AHP`*I+.DLZ3/P[NDI+G4H:,*
eofeof

print "test_data/multi-line    ";
    test('-e',example['test_data/multi-line'],[example['test_data/multi-line.ans']]);
# test_data/nkf-19-bug-1

example['test_data/nkf-19-bug-1'] = <<'eofeof'.unpack('u')[0]
,I*:DJZ2D"KK8QJ,*
eofeof

example['test_data/nkf-19-bug-1.ans'] = <<'eofeof'.unpack('u')[0]
8&R1")"8D*R0D&RA""ALD0CI81B,;*$(*
eofeof

print "test_data/nkf-19-bug-1    ";
    test('-Ej',example['test_data/nkf-19-bug-1'],[example['test_data/nkf-19-bug-1.ans']]);
# test_data/nkf-19-bug-2

example['test_data/nkf-19-bug-2'] = <<'eofeof'.unpack('u')[0]
%I-NDL@H`
eofeof

example['test_data/nkf-19-bug-2.ans'] = <<'eofeof'.unpack('u')[0]
%I-NDL@H`
eofeof

print "test_data/nkf-19-bug-2    ";
    test('-Ee',example['test_data/nkf-19-bug-2'],[example['test_data/nkf-19-bug-2.ans']]);
# test_data/nkf-19-bug-3

example['test_data/nkf-19-bug-3'] = <<'eofeof'.unpack('u')[0]
8[;'Q\,&L"N6ZSN\*\NT)ON7.SL_+"0D*
eofeof

example['test_data/nkf-19-bug-3.ans'] = <<'eofeof'.unpack('u')[0]
8[;'Q\,&L"N6ZSN\*\NT)ON7.SL_+"0D*
eofeof

print "test_data/nkf-19-bug-3    ";
    test('-e',example['test_data/nkf-19-bug-3'],[example['test_data/nkf-19-bug-3.ans']]);
# test_data/non-strict-mime

example['test_data/non-strict-mime'] = <<'eofeof'.unpack('u')[0]
M/3])4T\M,C`R,BU*4#]"/PIG<U-#;V]+.6=R-D-O;TQ%9W1Y0W0T1D-$46].
M0V\V16=S,D]N;T999S1Y1%=)3$IG=4-0:UD*2W!G<FU#>$E+:6=R,D-V;TMI
,9W-30V]O3&,*/ST*
eofeof

example['test_data/non-strict-mime.ans'] = <<'eofeof'.unpack('u')[0]
M&R1")$8D)"0_)$`D)"1&)%XD.2$C&RA"#0H-"ALD0CMD)$\[?B$Y)6PE.21+
<)&(]<20K)#LD1B0D)#\D0"0D)$8D)"1>&RA""@``
eofeof

print "test_data/non-strict-mime    ";
    test('-jTmN',example['test_data/non-strict-mime'],[example['test_data/non-strict-mime.ans']]);
# test_data/q-encode-softrap

example['test_data/q-encode-softrap'] = <<'eofeof'.unpack('u')[0]
H/3%")$(T03MZ)3T*,R$\)4DD3CTQ0BA""CTQ0B1"2E$T.3TQ0BA""@``
eofeof

example['test_data/q-encode-softrap.ans'] = <<'eofeof'.unpack('u')[0]
>&R1"-$$[>B4S(3PE221.&RA""ALD0DI1-#D;*$(*
eofeof

print "test_data/q-encode-softrap    ";
    test('-jTmQ',example['test_data/q-encode-softrap'],[example['test_data/q-encode-softrap.ans']]);
# test_data/rot13

example['test_data/rot13'] = <<'eofeof'.unpack('u')[0]
MI+.D\Z3+I,&DSZ&BS:W"]*3(I*2DI*3>I+FAHPH*;FMF('9E<BXQ+CDR(*3R
MS?C-T:2UI+NDQJ2DI+^DP*2DI,:DI*3>I+FDK*&B05-#24D@I,O"T*2WI,8@
M4D]4,3,@I*P*P+6DMZ2OQK"DI*3&I*2DRJ2DI.BDIJ3'H:*PRK*\I,ZDZ*2F
MI,O*T;2YI+6D[*3>I+ND\Z&C"@HE(&5C:&\@)VAO9V4G('P@;FMF("UR"FAO
#9V4*
eofeof

example['test_data/rot13.ans'] = <<'eofeof'.unpack('u')[0]
M&R1"4V)31%-Z4W!3?E!1?%QQ15-W4U-34U,O4VA04ALH0@H*87AS(&ER92XQ
M+CDR(!LD0E-#?$E\(E-D4VI3=5-34VY3;U-34W534U,O4VA36U!1&RA"3D90
M5E8@&R1"4WIQ(5-F4W4;*$(@14)',3,@&R1"4UL;*$(*&R1";V139E->=5]3
M4U-U4U-3>5-34SE355-V4%%?>6%K4WU3.5-54WIY(F-H4V13/5,O4VI31%!2
A&RA""@HE(')P=6(@)W5B='(G('P@87AS("UE"G5B='(*
eofeof

print "test_data/rot13    ";
    test('-jr',example['test_data/rot13'],[example['test_data/rot13.ans']]);
# test_data/slash

example['test_data/slash'] = <<'eofeof'.unpack('u')[0]
7("`]/U8\5"U5.5=%2RTK.U<U32LE+PH`
eofeof

example['test_data/slash.ans'] = <<'eofeof'.unpack('u')[0]
7("`]/U8\5"U5.5=%2RTK.U<U32LE+PH`
eofeof

print "test_data/slash    ";
    test(' ',example['test_data/slash'],[example['test_data/slash.ans']]);
# test_data/z1space-0

example['test_data/z1space-0'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

example['test_data/z1space-0.ans'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

print "test_data/z1space-0    ";
    test('-e -Z',example['test_data/z1space-0'],[example['test_data/z1space-0.ans']]);
# test_data/z1space-1

example['test_data/z1space-1'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

example['test_data/z1space-1.ans'] = <<'eofeof'.unpack('u')[0]
!(```
eofeof

print "test_data/z1space-1    ";
    test('-e -Z1',example['test_data/z1space-1'],[example['test_data/z1space-1.ans']]);
# test_data/z1space-2

example['test_data/z1space-2'] = <<'eofeof'.unpack('u')[0]
"H:$`
eofeof

example['test_data/z1space-2.ans'] = <<'eofeof'.unpack('u')[0]
"("``
eofeof

print "test_data/z1space-2    ";
    test('-e -Z2',example['test_data/z1space-2'],[example['test_data/z1space-2.ans']]);

# end
