# frozen_string_literal: true

# This is generated by generate_spdx_license_list.rb, any edits to this
# file will be discarded.

require_relative "../text"

class Gem::Licenses
  extend Gem::Text

  NONSTANDARD = "Nonstandard"
  LICENSE_REF = "LicenseRef-.+"

  # Software Package Data Exchange (SPDX) standard open-source software
  # license identifiers
  LICENSE_IDENTIFIERS = %w[
    0BSD
    AAL
    ADSL
    AFL-1.1
    AFL-1.2
    AFL-2.0
    AFL-2.1
    AFL-3.0
    AGPL-1.0
    AGPL-1.0-only
    AGPL-1.0-or-later
    AGPL-3.0
    AGPL-3.0-only
    AGPL-3.0-or-later
    AMDPLPA
    AML
    AMPAS
    ANTLR-PD
    ANTLR-PD-fallback
    APAFML
    APL-1.0
    APSL-1.0
    APSL-1.1
    APSL-1.2
    APSL-2.0
    Abstyles
    Adobe-2006
    Adobe-Glyph
    Afmparse
    Aladdin
    Apache-1.0
    Apache-1.1
    Apache-2.0
    App-s2p
    Arphic-1999
    Artistic-1.0
    Artistic-1.0-Perl
    Artistic-1.0-cl8
    Artistic-2.0
    BSD-1-Clause
    BSD-2-Clause
    BSD-2-Clause-FreeBSD
    BSD-2-Clause-NetBSD
    BSD-2-Clause-Patent
    BSD-2-Clause-Views
    BSD-3-Clause
    BSD-3-Clause-Attribution
    BSD-3-Clause-Clear
    BSD-3-Clause-LBNL
    BSD-3-Clause-Modification
    BSD-3-Clause-No-Military-License
    BSD-3-Clause-No-Nuclear-License
    BSD-3-Clause-No-Nuclear-License-2014
    BSD-3-Clause-No-Nuclear-Warranty
    BSD-3-Clause-Open-MPI
    BSD-4-Clause
    BSD-4-Clause-Shortened
    BSD-4-Clause-UC
    BSD-Protection
    BSD-Source-Code
    BSL-1.0
    BUSL-1.1
    Baekmuk
    Bahyph
    Barr
    Beerware
    BitTorrent-1.0
    BitTorrent-1.1
    Bitstream-Vera
    BlueOak-1.0.0
    Borceux
    C-UDA-1.0
    CAL-1.0
    CAL-1.0-Combined-Work-Exception
    CATOSL-1.1
    CC-BY-1.0
    CC-BY-2.0
    CC-BY-2.5
    CC-BY-2.5-AU
    CC-BY-3.0
    CC-BY-3.0-AT
    CC-BY-3.0-DE
    CC-BY-3.0-IGO
    CC-BY-3.0-NL
    CC-BY-3.0-US
    CC-BY-4.0
    CC-BY-NC-1.0
    CC-BY-NC-2.0
    CC-BY-NC-2.5
    CC-BY-NC-3.0
    CC-BY-NC-3.0-DE
    CC-BY-NC-4.0
    CC-BY-NC-ND-1.0
    CC-BY-NC-ND-2.0
    CC-BY-NC-ND-2.5
    CC-BY-NC-ND-3.0
    CC-BY-NC-ND-3.0-DE
    CC-BY-NC-ND-3.0-IGO
    CC-BY-NC-ND-4.0
    CC-BY-NC-SA-1.0
    CC-BY-NC-SA-2.0
    CC-BY-NC-SA-2.0-FR
    CC-BY-NC-SA-2.0-UK
    CC-BY-NC-SA-2.5
    CC-BY-NC-SA-3.0
    CC-BY-NC-SA-3.0-DE
    CC-BY-NC-SA-3.0-IGO
    CC-BY-NC-SA-4.0
    CC-BY-ND-1.0
    CC-BY-ND-2.0
    CC-BY-ND-2.5
    CC-BY-ND-3.0
    CC-BY-ND-3.0-DE
    CC-BY-ND-4.0
    CC-BY-SA-1.0
    CC-BY-SA-2.0
    CC-BY-SA-2.0-UK
    CC-BY-SA-2.1-JP
    CC-BY-SA-2.5
    CC-BY-SA-3.0
    CC-BY-SA-3.0-AT
    CC-BY-SA-3.0-DE
    CC-BY-SA-4.0
    CC-PDDC
    CC0-1.0
    CDDL-1.0
    CDDL-1.1
    CDL-1.0
    CDLA-Permissive-1.0
    CDLA-Permissive-2.0
    CDLA-Sharing-1.0
    CECILL-1.0
    CECILL-1.1
    CECILL-2.0
    CECILL-2.1
    CECILL-B
    CECILL-C
    CERN-OHL-1.1
    CERN-OHL-1.2
    CERN-OHL-P-2.0
    CERN-OHL-S-2.0
    CERN-OHL-W-2.0
    CNRI-Jython
    CNRI-Python
    CNRI-Python-GPL-Compatible
    COIL-1.0
    CPAL-1.0
    CPL-1.0
    CPOL-1.02
    CUA-OPL-1.0
    Caldera
    ClArtistic
    Community-Spec-1.0
    Condor-1.1
    Crossword
    CrystalStacker
    Cube
    D-FSL-1.0
    DL-DE-BY-2.0
    DOC
    DRL-1.0
    DSDP
    Dotseqn
    ECL-1.0
    ECL-2.0
    EFL-1.0
    EFL-2.0
    EPICS
    EPL-1.0
    EPL-2.0
    EUDatagrid
    EUPL-1.0
    EUPL-1.1
    EUPL-1.2
    Elastic-2.0
    Entessa
    ErlPL-1.1
    Eurosym
    FDK-AAC
    FSFAP
    FSFUL
    FSFULLR
    FSFULLRWD
    FTL
    Fair
    Frameworx-1.0
    FreeBSD-DOC
    FreeImage
    GD
    GFDL-1.1
    GFDL-1.1-invariants-only
    GFDL-1.1-invariants-or-later
    GFDL-1.1-no-invariants-only
    GFDL-1.1-no-invariants-or-later
    GFDL-1.1-only
    GFDL-1.1-or-later
    GFDL-1.2
    GFDL-1.2-invariants-only
    GFDL-1.2-invariants-or-later
    GFDL-1.2-no-invariants-only
    GFDL-1.2-no-invariants-or-later
    GFDL-1.2-only
    GFDL-1.2-or-later
    GFDL-1.3
    GFDL-1.3-invariants-only
    GFDL-1.3-invariants-or-later
    GFDL-1.3-no-invariants-only
    GFDL-1.3-no-invariants-or-later
    GFDL-1.3-only
    GFDL-1.3-or-later
    GL2PS
    GLWTPL
    GPL-1.0
    GPL-1.0+
    GPL-1.0-only
    GPL-1.0-or-later
    GPL-2.0
    GPL-2.0+
    GPL-2.0-only
    GPL-2.0-or-later
    GPL-2.0-with-GCC-exception
    GPL-2.0-with-autoconf-exception
    GPL-2.0-with-bison-exception
    GPL-2.0-with-classpath-exception
    GPL-2.0-with-font-exception
    GPL-3.0
    GPL-3.0+
    GPL-3.0-only
    GPL-3.0-or-later
    GPL-3.0-with-GCC-exception
    GPL-3.0-with-autoconf-exception
    Giftware
    Glide
    Glulxe
    HPND
    HPND-sell-variant
    HTMLTIDY
    HaskellReport
    Hippocratic-2.1
    IBM-pibs
    ICU
    IJG
    IPA
    IPL-1.0
    ISC
    ImageMagick
    Imlib2
    Info-ZIP
    Intel
    Intel-ACPI
    Interbase-1.0
    JPNIC
    JSON
    Jam
    JasPer-2.0
    Knuth-CTAN
    LAL-1.2
    LAL-1.3
    LGPL-2.0
    LGPL-2.0+
    LGPL-2.0-only
    LGPL-2.0-or-later
    LGPL-2.1
    LGPL-2.1+
    LGPL-2.1-only
    LGPL-2.1-or-later
    LGPL-3.0
    LGPL-3.0+
    LGPL-3.0-only
    LGPL-3.0-or-later
    LGPLLR
    LPL-1.0
    LPL-1.02
    LPPL-1.0
    LPPL-1.1
    LPPL-1.2
    LPPL-1.3a
    LPPL-1.3c
    LZMA-SDK-9.11-to-9.20
    LZMA-SDK-9.22
    Latex2e
    Leptonica
    LiLiQ-P-1.1
    LiLiQ-R-1.1
    LiLiQ-Rplus-1.1
    Libpng
    Linux-OpenIB
    Linux-man-pages-copyleft
    MIT
    MIT-0
    MIT-CMU
    MIT-Modern-Variant
    MIT-advertising
    MIT-enna
    MIT-feh
    MIT-open-group
    MITNFA
    MPL-1.0
    MPL-1.1
    MPL-2.0
    MPL-2.0-no-copyleft-exception
    MS-LPL
    MS-PL
    MS-RL
    MTLL
    MakeIndex
    Minpack
    MirOS
    Motosoto
    MulanPSL-1.0
    MulanPSL-2.0
    Multics
    Mup
    NAIST-2003
    NASA-1.3
    NBPL-1.0
    NCGL-UK-2.0
    NCSA
    NGPL
    NICTA-1.0
    NIST-PD
    NIST-PD-fallback
    NLOD-1.0
    NLOD-2.0
    NLPL
    NOSL
    NPL-1.0
    NPL-1.1
    NPOSL-3.0
    NRL
    NTP
    NTP-0
    Naumen
    Net-SNMP
    NetCDF
    Newsletr
    Nokia
    Noweb
    Nunit
    O-UDA-1.0
    OCCT-PL
    OCLC-2.0
    ODC-By-1.0
    ODbL-1.0
    OFL-1.0
    OFL-1.0-RFN
    OFL-1.0-no-RFN
    OFL-1.1
    OFL-1.1-RFN
    OFL-1.1-no-RFN
    OGC-1.0
    OGDL-Taiwan-1.0
    OGL-Canada-2.0
    OGL-UK-1.0
    OGL-UK-2.0
    OGL-UK-3.0
    OGTSL
    OLDAP-1.1
    OLDAP-1.2
    OLDAP-1.3
    OLDAP-1.4
    OLDAP-2.0
    OLDAP-2.0.1
    OLDAP-2.1
    OLDAP-2.2
    OLDAP-2.2.1
    OLDAP-2.2.2
    OLDAP-2.3
    OLDAP-2.4
    OLDAP-2.5
    OLDAP-2.6
    OLDAP-2.7
    OLDAP-2.8
    OML
    OPL-1.0
    OPUBL-1.0
    OSET-PL-2.1
    OSL-1.0
    OSL-1.1
    OSL-2.0
    OSL-2.1
    OSL-3.0
    OpenSSL
    PDDL-1.0
    PHP-3.0
    PHP-3.01
    PSF-2.0
    Parity-6.0.0
    Parity-7.0.0
    Plexus
    PolyForm-Noncommercial-1.0.0
    PolyForm-Small-Business-1.0.0
    PostgreSQL
    Python-2.0
    Python-2.0.1
    QPL-1.0
    Qhull
    RHeCos-1.1
    RPL-1.1
    RPL-1.5
    RPSL-1.0
    RSA-MD
    RSCPL
    Rdisc
    Ruby
    SAX-PD
    SCEA
    SGI-B-1.0
    SGI-B-1.1
    SGI-B-2.0
    SHL-0.5
    SHL-0.51
    SISSL
    SISSL-1.2
    SMLNJ
    SMPPL
    SNIA
    SPL-1.0
    SSH-OpenSSH
    SSH-short
    SSPL-1.0
    SWL
    Saxpath
    SchemeReport
    Sendmail
    Sendmail-8.23
    SimPL-2.0
    Sleepycat
    Spencer-86
    Spencer-94
    Spencer-99
    StandardML-NJ
    SugarCRM-1.1.3
    TAPR-OHL-1.0
    TCL
    TCP-wrappers
    TMate
    TORQUE-1.1
    TOSL
    TU-Berlin-1.0
    TU-Berlin-2.0
    UCL-1.0
    UPL-1.0
    Unicode-DFS-2015
    Unicode-DFS-2016
    Unicode-TOU
    Unlicense
    VOSTROM
    VSL-1.0
    Vim
    W3C
    W3C-19980720
    W3C-20150513
    WTFPL
    Watcom-1.0
    Wsuipa
    X11
    X11-distribute-modifications-variant
    XFree86-1.1
    XSkat
    Xerox
    Xnet
    YPL-1.0
    YPL-1.1
    ZPL-1.1
    ZPL-2.0
    ZPL-2.1
    Zed
    Zend-2.0
    Zimbra-1.3
    Zimbra-1.4
    Zlib
    blessing
    bzip2-1.0.5
    bzip2-1.0.6
    checkmk
    copyleft-next-0.3.0
    copyleft-next-0.3.1
    curl
    diffmark
    dvipdfm
    eCos-2.0
    eGenix
    etalab-2.0
    gSOAP-1.3b
    gnuplot
    iMatix
    libpng-2.0
    libselinux-1.0
    libtiff
    libutil-David-Nugent
    mpi-permissive
    mpich2
    mplus
    psfrag
    psutils
    wxWindows
    xinetd
    xpp
    zlib-acknowledgement
  ].freeze

  # exception identifiers
  EXCEPTION_IDENTIFIERS = %w[
    389-exception
    Autoconf-exception-2.0
    Autoconf-exception-3.0
    Bison-exception-2.2
    Bootloader-exception
    CLISP-exception-2.0
    Classpath-exception-2.0
    DigiRule-FOSS-exception
    FLTK-exception
    Fawkes-Runtime-exception
    Font-exception-2.0
    GCC-exception-2.0
    GCC-exception-3.1
    GPL-3.0-linking-exception
    GPL-3.0-linking-source-exception
    GPL-CC-1.0
    GStreamer-exception-2005
    GStreamer-exception-2008
    KiCad-libraries-exception
    LGPL-3.0-linking-exception
    LLVM-exception
    LZMA-exception
    Libtool-exception
    Linux-syscall-note
    Nokia-Qt-exception-1.1
    OCCT-exception-1.0
    OCaml-LGPL-linking-exception
    OpenJDK-assembly-exception-1.0
    PS-or-PDF-font-exception-20170817
    Qt-GPL-exception-1.0
    Qt-LGPL-exception-1.1
    Qwt-exception-1.0
    SHL-2.0
    SHL-2.1
    Swift-exception
    Universal-FOSS-exception-1.0
    WxWindows-exception-3.1
    eCos-exception-2.0
    freertos-exception-2.0
    gnu-javamail-exception
    i2p-gpl-java-exception
    mif-exception
    openvpn-openssl-exception
    u-boot-exception-2.0
    x11vnc-openssl-exception
  ].freeze

  REGEXP = /
    \A
    (?:
      #{Regexp.union(LICENSE_IDENTIFIERS)}
      \+?
      (?:\s WITH \s #{Regexp.union(EXCEPTION_IDENTIFIERS)})?
      | #{NONSTANDARD}
      | #{LICENSE_REF}
    )
    \Z
  /ox.freeze

  def self.match?(license)
    !REGEXP.match(license).nil?
  end

  def self.suggestions(license)
    by_distance = LICENSE_IDENTIFIERS.group_by do |identifier|
      levenshtein_distance(identifier, license)
    end
    lowest = by_distance.keys.min
    return unless lowest < license.size
    by_distance[lowest]
  end
end
