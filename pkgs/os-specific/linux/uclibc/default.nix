{ stdenv, buildPackages
, fetchzip, linuxHeaders, libiconvReal
, buildPlatform, hostPlatform
, extraConfig ? ""
}:

let
  configParser = ''
    function parseconfig {
        set -x
        while read LINE; do
            NAME=`echo "$LINE" | cut -d \  -f 1`
            OPTION=`echo "$LINE" | cut -d \  -f 2`

            if test -z "$NAME"; then
                continue
            fi

            echo "parseconfig: removing $NAME"
            sed -i /^$NAME=/d .config

            #if test "$OPTION" != n; then
                echo "parseconfig: setting $NAME=$OPTION"
                echo "$NAME=$OPTION" >> .config
            #fi
        done
        set +x
    }
  '';

  # UCLIBC_SUSV4_LEGACY defines 'tmpnam', needed for gcc libstdc++ builds.
  nixConfig = ''
    RUNTIME_PREFIX "/"
    DEVEL_PREFIX "/"
    UCLIBC_HAS_WCHAR y
    UCLIBC_HAS_FTW y
    UCLIBC_HAS_RPC y
    DO_C99_MATH y
    UCLIBC_HAS_PROGRAM_INVOCATION_NAME y
    UCLIBC_SUSV4_LEGACY y
    UCLIBC_HAS_THREADS_NATIVE y
    KERNEL_HEADERS "${linuxHeaders}/include"
  '' + stdenv.lib.optionalString (stdenv.isAarch32 && buildPlatform != hostPlatform) ''
    CONFIG_ARM_EABI y
    ARCH_WANTS_BIG_ENDIAN n
    ARCH_BIG_ENDIAN n
    ARCH_WANTS_LITTLE_ENDIAN y
    ARCH_LITTLE_ENDIAN y
    UCLIBC_HAS_FPU n
  '';

  name = "uclibc-0.9.34-pre-20150131";
  rev = "343f6b8f1f754e397632b0552e4afe586c8b392b";

in

stdenv.mkDerivation {
  inherit name;

  src = fetchzip {
    name = name + "-source";
    url = "http://git.uclibc.org/uClibc/snapshot/uClibc-${rev}.tar.bz2";
    sha256 = "1kgylzpid7da5i7wz7slh5q9rnq1m8bv5h9ilm76g0xwc2iwlhbw";
  };

  # 'ftw' needed to build acl, a coreutils dependency
  configurePhase = ''
    make defconfig
    ${configParser}
    cat << EOF | parseconfig
    ${nixConfig}
    ${extraConfig}
    ${hostPlatform.platform.uclibc.extraConfig or ""}
    EOF
    ( set +o pipefail; yes "" | make oldconfig )
  '';

  hardeningDisable = [ "stackprotector" ];

  # Cross stripping hurts.
  dontStrip = stdenv.hostPlatform != stdenv.buildPlatform;

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  makeFlags = [
    "ARCH=${hostPlatform.parsed.cpu.name}"
    "VERBOSE=1"
  ] ++ stdenv.lib.optionals (stdenv.buildPlatform != stdenv.hostPlatform) [
    "CROSS=${stdenv.cc.targetPrefix}"
  ];

  # `make libpthread/nptl/sysdeps/unix/sysv/linux/lowlevelrwlock.h`:
  # error: bits/sysnum.h: No such file or directory
  enableParallelBuilding = false;

  installPhase = ''
    mkdir -p $out
    make PREFIX=$out VERBOSE=1 install
    (cd $out/include && ln -s $(ls -d ${linuxHeaders}/include/* | grep -v "scsi$") .)
    # libpthread.so may not exist, so I do || true
    sed -i s@/lib/@$out/lib/@g $out/lib/libc.so $out/lib/libpthread.so || true
  '';

  passthru = {
    # Derivations may check for the existance of this attribute, to know what to link to.
    libiconv = libiconvReal;
  };

  meta = with stdenv.lib; {
    homepage = http://www.uclibc.org/;
    description = "A small implementation of the C library";
    maintainers = with maintainers; [ rasendubi ];
    license = licenses.lgpl2;
    platforms = platforms.linux;
    broken = hostPlatform.isAarch64;
  };
}
