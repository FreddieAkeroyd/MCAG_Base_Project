#!/bin/sh
APPXX=eemcu
export APPXX

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)

INSTALLED_EPICS=../../../.epics.$(hostname).$uname_s.$uname_m

if test -r $INSTALLED_EPICS; then
  echo INSTALLED_EPICS=$INSTALLED_EPICS
. $INSTALLED_EPICS
else
  echo not found: INSTALLED_EPICS=$INSTALLED_EPICS
fi


if test -z "$EPICS_BASE";then
  echo >&2 "EPICS_BASE" is not set
  exit 1
fi

makeCleanClean() {
  echo makeCleanClean
  test -d builddir && rm -rf builddir/
  make -f  Makefile.epics clean
  make -f  Makefile.epics uninstall
  make -f  Makefile.epics clean || :
}

../checkws.sh || {
  echo >&2 whitespace damage
  exit 2
}
MOTORIP=127.0.0.1
MOTORPORT=5024

case "$1" in
  TwoAxis)
  MOTORCFG=.TwoAxis
  shift
  ;;
  SolAxis)
  MOTORCFG=.SolAxis
  shift
  ;;
  Sim8)
  MOTORCFG=.Sim8
  shift
  ;;
  *)
  MOTORCFG=
  echo >&2 $0 " SolAxis|TwoAxis|Sim8 <ip>[:port]"
  exit 1
  ;;
esac
export MOTORCFG
echo MOTORCFG=$MOTORCFG

if test -n "$1"; then
  # allow doit.sh host:port
  PORT=${1##*:}
  HOST=${1%:*}
  echo HOST=$HOST PORT=$PORT
  if test "$PORT" != "$HOST"; then
    MOTORPORT=$PORT
  fi
  echo HOST=$HOST MOTORPORT=$MOTORPORT
  MOTORIP=$HOST
  echo MOTORIP=$MOTORIP
fi
export MOTORIP MOTORPORT
setttings_file=./.set_${uname_s}_${uname_m}.txt
oldsetttings_file=./.set_${uname_s}_${uname_m}.old.txt
export setttings_file oldsetttings_file

set | grep EPICS_ | sort >"$setttings_file"
if ! test -f "$oldsetttings_file"; then
  make_clean_uninstall=y
  (
    makeCleanClean
  )
  cp "$setttings_file" "$oldsetttings_file"
else
 if ! diff "$oldsetttings_file" "$setttings_file" ; then
   make_clean_uninstall=y
   (
     . "$oldsetttings_file"
     makeCleanClean
   )
   rm -f "$oldsetttings_file"
 fi
fi

if ! test -d ${APPXX}App; then
  makeBaseApp.pl -t ioc $APPXX
fi &&
if ! test -d iocBoot; then
  makeBaseApp.pl -i -t ioc $APPXX
fi &&

if test -z "$EPICS_HOST_ARCH"; then
  echo >&2 EPICS_HOST_ARCH is not set
  exit 1
fi &&
TOP=$PWD &&
if test -d $EPICS_BASE/../modules/motor/Db; then
  EPICS_MOTOR_DB=$EPICS_BASE/../modules/motor/Db
elif test -d $EPICS_BASE/../modules/motor/db; then
  EPICS_MOTOR_DB=$EPICS_BASE/../modules/motor/db
elif test -d $EPICS_BASE/../modules/motor/dbd; then
  EPICS_MOTOR_DB=$EPICS_BASE/../modules/motor/dbd
elif test -n "$EPICS_BASES_PATH"; then
   echo >&2 found: EPICS_BASES_PATH=$EPICS_BASES_PATH
   echo >&2        EPICS_BASE=$EPICS_BASE
   mybasever=$(echo $EPICS_BASE | sed -e "s!^$EPICS_BASES_PATH/base-!!")
   echo >&2 mybasever=$mybasever
   EPICS_MOTOR_DB=$EPICS_MODULES_PATH/motor/6.8.1/$mybasever/dbd
   echo >&2 EPICS_MOTOR_DB=$EPICS_MOTOR_DB
   if ! test -d "$EPICS_MOTOR_DB"; then
     echo >&2 Not found EPICS_MOTOR_DB=$EPICS_MOTOR_DB
     exit 1
   fi
   EPICS_EEE=y
   export EPICS_EEE make_clean_uninstall
else
   echo >&2 Not found: $EPICS_BASE/../modules/motor/[dD]b
   echo >&2 Unsupported EPICS_BASE:$EPICS_BASE
  exit 1
fi &&
if ! test -d "$EPICS_MOTOR_DB"; then
  echo >&2 $EPICS_MOTOR_DB does not exist
  exit 1
fi
(
  cd configure &&
  if ! test -f RELEASE_usr_local; then
    git mv RELEASE RELEASE_usr_local
  fi &&
  sed <RELEASE_usr_local >RELEASE \
  -e "s%^EPICS_BASE=.*$%EPICS_BASE=$EPICS_BASE%" &&
  if  test -f MASTER_RELEASE; then
    if ! test -f MASTER_RELEASE_usr_local; then
      git mv MASTER_RELEASE MASTER_RELEASE_usr_local
    fi &&
    sed <MASTER_RELEASE_usr_local >MASTER_RELEASE \
      -e "s%^EPICS_BASE=.*$%EPICS_BASE=$EPICS_BASE%"
  fi
) &&
if test "x$make_clean_uninstall" = xy; then
  makeCleanClean
fi &&

if test "x$EPICS_EEE" = "xy"; then
  make install || {
    echo >&2 EEE
    exit 1
  }
else
  make -f Makefile.epics || {
    rm -f "$oldsetttings_file"
    make -f  Makefile.epics clean && make -f Makefile.epics  ||  exit 1
  }
fi
(
  envPathsdst=./envPaths.$EPICS_HOST_ARCH &&
  stcmddst=./st.cmd.$EPICS_HOST_ARCH &&
  cd ./iocBoot/ioc${APPXX}/ &&
  if test "x$EPICS_EEE" = "xy"; then
    stcmddst=./st.cmd${MOTORCFG}.EEE &&
    rm -f $stcmddst &&
    cat st-start.EEE st-main${MOTORCFG} |  \
      sed                                        \
      -e "s/__EPICS_HOST_ARCH/$EPICS_HOST_ARCH/" \
      -e "s/eemcu,USER/eemcu,$USER/" \
      -e "s/127.0.0.1:5024/$MOTORIP:$MOTORPORT/" |
    grep -v '^  *#' >$stcmddst || {
      echo >&2 can not create stcmddst $stcmddst
      exit 1
    }
    chmod -w $stcmddst &&
    chmod +x $stcmddst &&
    cmd=$(echo iocsh $stcmddst) &&
    echo PWD=$PWD cmd=$cmd &&
    eval $cmd
  else
    envPathssrc=./envPaths.empty &&
    if ! test -s "$envPathssrc"; then
      echo PWD=$PWD generating: "$envPathssrc"
      cat >"$envPathssrc" <<-\EOF
          #Do not edit, autogenerated from doit.sh
          epicsEnvSet("ARCH","__EPICS_HOST_ARCH")
          epicsEnvSet("IOC","ioc${APPXX}")
          epicsEnvSet("TOP","__TOP")
          epicsEnvSet("EPICS_BASE","__EPICS_BASE")
EOF
    else
      echo PWD=$PWD does exist: "$envPathssrc"
    fi &&
    rm -f $envPathsdst &&
    sed <$envPathssrc >$envPathsdst \
      -e "s/__EPICS_HOST_ARCH/$EPICS_HOST_ARCH/" \
      -e "s!__TOP!$TOP!" \
      -e "s!__EPICS_BASE!$EPICS_BASE!" \
      -e "s/__EPICS_HOST_ARCH/$EPICS_HOST_ARCH/"  &&
    rm -f $stcmddst &&
    cat st-start.epics st-main${MOTORCFG} st-end.epics |  \
      sed                                        \
      -e "s/__EPICS_HOST_ARCH/$EPICS_HOST_ARCH/" \
      -e "s/127.0.0.1:5024/$MOTORIP:$MOTORPORT/" \
      | grep -v '^  *#' >$stcmddst &&
    chmod -w $stcmddst &&
    chmod +x $stcmddst &&
    cp $envPathsdst st.gdb.$EPICS_HOST_ARCH &&
    egrep -v "envPaths|APPXX" $stcmddst >> st.gdb.$EPICS_HOST_ARCH
    egrep -v "^ *#" st.gdb.$EPICS_HOST_ARCH >xx
    echo PWD=$PWD $stcmddst
    $stcmddst
  fi
)

