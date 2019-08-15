#
# racc syntax checker
#

class M1::M2::ParserClass < S1::S2::SuperClass

  token A
      | B C

  convert
    A '5'
  end

  prechigh
    left B
  preclow

  start target

  expect 0

rule

  target: A B C
            {
              print 'abc'
            }
        | B C A
        | C B A
            {
              print 'cba'
            }
        | cont

  cont  : A c2 B c2 C

  c2    : C C C C C

end

---- inner

    junk code  !!!!

kjaljlajrlaolanbla  /// %%%  (*((( token rule
akiurtlajluealjflaj    @@@@   end end end end __END__
  laieu2o879urkq96ga(Q#*&%Q#
 #&lkji  END

         q395q?///  liutjqlkr7
