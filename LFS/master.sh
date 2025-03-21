#!/bin/bash

###################################
###	    FUNCTIONS		###
###################################


#############################################################


#-------------------------#
chapter_targets() {       #
#-------------------------#
# $1 is the chapter number. Pad it with 0 to the left to obtain a 2-digit
# number:
  printf -v dir chapter%02d $1

# $2 contains the build number if rebuilding for ICA
  if [[ -z "$2" ]] ; then
    local N=""
  else
    local N=-build_$2
    local CHROOT_TGT=""
    mkdir ${dir}$N
    cp ${dir}/* ${dir}$N
    for script in ${dir}$N/* ; do
      # Overwrite existing symlinks, files, and dirs
      sed -e 's/ln *-sv/&f/g' \
          -e 's/mv *-v/&f/g' \
          -e 's/mkdir *-v/&p/g' -i ${script}
      # Rename the scripts
      mv ${script} ${script}$N
    done
    # Remove Bzip2 binaries before make install (LFS-6.2 compatibility)
    sed -e 's@make install@rm -vf /usr/bin/bz*\n&@' -i ${dir}$N/*-bzip2$N
    # Remove openssl-<version> from /usr/share/doc (LFS-9.x), because
    # otherwise the mv command creates an openssl directory.
    sed -e 's@mv -v@rm -rfv /usr/share/doc/openssl-*\n&@' \
        -i ${dir}$N/*-openssl$N
  fi

  echo "${tab_}${GREEN}Processing... ${L_arrow}Chapter $1$N${R_arrow}"

  for file in ${dir}$N/* ; do
    # Keep the script file name
    this_script=`basename $file`

    # Some scripts need peculiar actions:
    # - Stripping at the end of system build: lfs.xsl does not generate
    #   correct commands if the user does not want to strip, so skip it
    #   in this case
    # - do not reinstall linux-headers when rebuilding
    # - grub config: must be done manually; skip it
    # - handle fstab and .config. Skip kernel if .config not supplied
    case "${this_script}" in
      *stripping*)     [[ "${STRIP}" = "n" ]] && continue ;;
      *linux-headers*) [[ -n "$N" ]] && continue ;;
      8*grub)          (( nb_chaps == 5 )) && continue ;;
      10*grub)         continue ;;
      *fstab)          [[ -z "${FSTAB}" ]] ||
                       [[ ${FSTAB} == $BUILDDIR/sources/fstab ]] ||
                       cp ${FSTAB} $BUILDDIR/sources/fstab ;;
      *kernel)         [[ -z ${CONFIG} ]] && continue
                       [[ ${CONFIG} == $BUILDDIR/sources/kernel-config ]] ||
                       cp ${CONFIG} $BUILDDIR/sources/kernel-config  ;;
    esac
    # Grab the name of the target
    # This is only used to check the name in "opt_override" or "BLACKLIST"
    name=`echo ${this_script} | sed -e 's@[0-9]\{3,4\}-@@' \
                                    -e 's@-pass[0-9]\{1\}@@' \
                                    -e 's@-libstdc++@@' \
                                    -e 's,'$N',,' \
                                    -e 's@-32@@'`

    # Find the name of the tarball and the version of the package
    # If it doesn't exist, we skip it in iterations rebuilds (except stripping
    # and revisedchroot, where .a and .la files are removed).
    pkg_tarball=$(sed -n 's/tar -xf \(.*\)/\1/p' $file)
    pkg_version=$(sed -n 's/VERSION=\(.*\)/\1/p' $file)

    if [[ "$pkg_tarball" = "" ]] && [[ -n "$N" ]] ; then
      case "${this_script}" in
        *stripping*|*cleanup*|*revised*) ;;
        *)  continue ;;
      esac
    fi

    # Append the name of the script to a list. The name of the
    # list is contained in the variable Makefile_target. We adjust this
    # variable at various points. Note that it is initialized to "SETUP"
    # in the main function, before calling this function for the first time.
    case "${this_script}" in
      *settingenvironment) Makefile_target=LUSER_TGT  ;;
      *changingowner     ) Makefile_target=SUDO_TGT   ;;
      *creatingdirs      ) Makefile_target=CHROOT_TGT ;;
      *bootscripts       ) Makefile_target=BOOT_TGT   ;; # case of sysv    book
      *network           ) Makefile_target=BOOT_TGT   ;; # case of systemd book
    esac
    eval $Makefile_target=\"\$$Makefile_target ${this_script}\"

    #--------------------------------------------------------------------#
    #         >>>>>>>> START BUILDING A Makefile ENTRY <<<<<<<<          #
    #--------------------------------------------------------------------#

    # Drop in the name of the target on a new line, and the previous target
    # as a dependency. Also call the echo_message function.
    case $Makefile_target in
      CHROOT_TGT)  CHROOT_wrt_target "${this_script}" "$PREV" "$pkg_version" ;;
      *)            LUSER_wrt_target "${this_script}" "$PREV" "$pkg_version" ;;
    esac

    # If $pkg_tarball isn't empty, we've got a package...
    if [ "$pkg_tarball" != "" ] ; then
      # Touch timestamp file if installed files logs shall be created.
      # But only for the final install chapter and not when rebuilding it
      if [ "${INSTALL_LOG}" = "y" ] &&
         (( 1+nb_chaps <= $1 )) &&
         [ "x$N" = x ] ; then
        CHROOT_wrt_TouchTimestamp
      fi
      # Always initialize the test log file, since the test instructions may
      # be "uncommented" by the user
      case $Makefile_target in
       CHROOT_TGT)  CHROOT_wrt_test_log "${this_script}" "$pkg_version" ;;
       LUSER_TGT )  LUSER_wrt_test_log  "${this_script}" "$pkg_version" ;;
      esac

      # If using optimizations, write the instructions
      case "${OPTIMIZE}$1${nb_chaps}${this_script}${REALSBU}" in
          0* | *binutils-pass1y | 15* | 167* | 177*) ;;
          *kernel*) ;; # No CFLAGS for kernel
          *)  wrt_optimize "$name" ;;
      esac
      # There is no need to tweak MAKEFLAGS anymore, this is done
      # by lfs.xsl. But still, NINJAJOBS needs to be set if
      # N_PARALLEL is defined.
      if [ -n "N_PARALLEL" ]; then
         wrt_makeflags "$name" "$JH_MAKEFLAGS" "$N_PARALLEL"
      fi
    fi # end of package specific instructions

# Some scriptlet have a special treatment; otherwise standard
    case "${this_script}" in
      *addinguser)
(
# /var/lib may already exist and be owned by root if blfs tools
# have been installed.
cat << EOF
	@export LFS=\$(MOUNT_PT) && \\
	\$(CMDSDIR)/`dirname $file`/\$@ >> \$(LOGDIR)/\$@ 2>&1; \\
	\$(PRT_DU) >>logs/\$@
	@chown \$(LUSER):\$(LGROUP) envars
	@if [ -d "\$(MOUNT_PT)/var/lib" ]; then \\
	    chown \$(LUSER):\$(LGROUP) \$(MOUNT_PT)/var/lib; \\
	fi
	@chmod -R a+wt $JHALFSDIR
	@chmod a+wt \$(SRCSDIR)
EOF
) >> $MKFILE.tmp
	      ;;
      *settingenvironment)
(
cat << EOF
	@cd && \\
	function source() { true; } && \\
	export -f source && \\
	\$(CMDSDIR)/`dirname $file`/\$@ >> \$(LOGDIR)/\$@ 2>&1 && \\
	sed 's|/mnt/lfs|\$(MOUNT_PT)|' -i .bashrc && \\
	echo source $JHALFSDIR/envars >> .bashrc
	@\$(PRT_DU) >>logs/\$@
EOF
) >> $MKFILE.tmp
	      ;;
      *fstab) if [[ -n "$FSTAB" ]]; then
                CHROOT_wrt_CopyFstab
              else
                CHROOT_wrt_RunAsRoot "$file"
              fi
              ;;

      *)
         # Insert date and disk usage at the top of the log file, the script
         # run and date and disk usage again at the bottom of the log file.
         case "${Makefile_target}" in
           SETUP_TGT | SUDO_TGT)  wrt_RunAsRoot "$file" "$pkg_version" ;;
           LUSER_TGT)             LUSER_wrt_RunAsUser "$file" "$pkg_version" ;;
           CHROOT_TGT | BOOT_TGT) CHROOT_wrt_RunAsRoot "$file" "$pkg_version" ;;
         esac
	      ;;
    esac

    # Write installed files log and remove the build directory(ies)
    # except if the package build fails.
    if [ "$pkg_tarball" != "" ] ; then
      if [ "${INSTALL_LOG}" = "y" ] &&
         (( 1+nb_chaps <= $1 )) &&
         [ "x${N}" = "x" ] ; then
        CHROOT_wrt_LogNewFiles "${this_script}"
      fi
    fi

    # Include a touch of the target name so make can check
    # if it's already been made.
    wrt_touch
    #
    #--------------------------------------------------------------------#
    #              >>>>>>>> END OF Makefile ENTRY <<<<<<<<               #
    #--------------------------------------------------------------------#

    # Keep the script file name for Makefile dependencies.
    PREV=${this_script}
    # Set "system_build" var for iteration targets
    if [ -z "$N" ] && (( 1+nb_chaps == $1 )); then
      system_build="$system_build $this_script"
    fi

  done  # end for file in $dir/*
  # Set "system_build" when rebuilding: note the CHROOT_TGT is local
  # in that case.
  if [ -n "$N" ]; then
    system_build="$CHROOT_TGT"
  fi
}

#----------------------------#
build_Makefile() {           #
#----------------------------#

  echo "Creating Makefile... ${BOLD}START${OFF}"

  cd "$JHALFSDIR/$COMMANDS"

  # Start with empty files
  >$MKFILE
  >$MKFILE.tmp

  # Ensure the first dependency is empty
  unset PREV

  # We begin with the SETUP target; successive targets will be assigned in
  # the chapter_targets function.
  Makefile_target=SETUP_TGT

  # We need to know the chapter numbering, which depends on the version
  # of the book. Use the number of subdirs to know which version we have
  chaps=($(echo chapter*))
  nb_chaps=${#chaps[*]} # 5 if classical version, 7 if new version
# DEBUG
#  echo chaps: ${chaps[*]}
#  echo nb_chaps: $nb_chaps
# end DEBUG

  # Make a temporary file with all script targets
  for (( i = 4; i < nb_chaps+4; i++ )); do
    chapter_targets $i
    if (( i ==  nb_chaps )); then : # we have finished temporary tools
      # Add the save target, if needed
      [[ "$SAVE_CH5" = "y" ]] && wrt_save_target $Makefile_target
    fi
    if (( i ==  1+nb_chaps )); then : # we have finished final system
      # Add the iterations targets, if needed
      [[ "$COMPARE" = "y" ]] && wrt_compare_targets $i
    fi
  done
  # Add the CUSTOM_TOOLS targets, if needed
  [[ "$CUSTOM_TOOLS" = "y" ]] && wrt_CustomTools_target

  # Add a header, some variables and include the function file
  # to the top of the real Makefile.
  wrt_Makefile_header

  # Add chroot commands
  CHROOT_LOC="`whereis -b chroot | cut -d " " -f2`"
  i=1
  for file in ../chroot-scripts/*chroot* ; do
    chroot=`cat $file | \
            perl -pe 's|\\\\\n||g' | \
            tr -s [:space:] | \
            grep chroot | \
            sed -e "s|chroot|$CHROOT_LOC|" \
                -e 's|\\$|&&|g' \
                -e 's|"$$LFS"|$(MOUNT_PT)|'`
    echo -e "CHROOT$i= $chroot\n" >> $MKFILE
    i=`expr $i + 1`
  done

  # If CPUSET is defined and not equal to "all", then we define a first target
  # that calls a script which re-enters make calling target all
  if [ -n "$CPUSET" ] && [ "$CPUSET" != all ]; then
(
    cat << EOF

all-with-cpuset:
	@CPUSPEC="\$(CPUSET)" ./run-in-cgroup.sh \$(MAKE) all
EOF
) >> $MKFILE
  fi
  # Drop in the main target 'all:' and the chapter targets with each sub-target
  # as a dependency. Also prevent running targets in parallel.
(
    cat << EOF

.NOTPARALLEL:

all:	ck_UID ck_terminal ck_mountpoint mk_SETUP mk_LUSER mk_SUDO mk_CHROOT mk_BOOT create-sbu_du-report mk_BLFS_TOOL mk_CUSTOM_TOOLS
	@sudo env LFS=\$(MOUNT_PT) kernfs-scripts/teardown.sh
EOF
) >> $MKFILE
# With systemd, the commands in chapter 9 do not create a
# valid /etc/resolv.conf, so that if blfs_tools are installed, and
# make-ca is run, it cannot connect. In this case, resolv.conf
# from the host has been copied, and we need to remove it now.
if [ "$INITSYS" = systemd ]; then
(
    cat << EOF
	@sudo rm -v \$(MOUNT_PT)/etc/resolv.conf
EOF
) >> $MKFILE
fi
(
    cat << EOF
	@sudo make do_housekeeping
	@echo $VERSION > lfs-release && \\
	sudo mv lfs-release \$(MOUNT_PT)/etc && \\
	sudo chown root:root \$(MOUNT_PT)/etc/lfs-release
	@/bin/echo -e -n \\
	DISTRIB_ID=\\"Linux From Scratch\\"\\\\n\\
	DISTRIB_RELEASE=\\"$VERSION\\"\\\\n\\
	DISTRIB_CODENAME=\\"$(whoami)-jhalfs\\"\\\\n\\
	DISTRIB_DESCRIPTION=\\"Linux From Scratch\\"\\\\n\\
	> lsb-release && \\
	sudo mv lsb-release \$(MOUNT_PT)/etc && \\
	sudo chown root:root \$(MOUNT_PT)/etc/lsb-release
	@/bin/echo -e -n \\
	NAME=\\"Linux From Scratch\\"\\\\n\\
	VERSION=\\"$VERSION\\"\\\\n\\
	ID=lfs\\\\n\\
	PRETTY_NAME=\\"Linux From Scratch $VERSION\\"\\\\n\\
	VERSION_CODENAME=\\"$(whoami)-jhalfs\\"\\\\n\\
	> os-release && \\
	sudo mv os-release \$(MOUNT_PT)/etc && \\
	sudo chown root:root \$(MOUNT_PT)/etc/os-release
	@\$(call echo_finished,$VERSION)

ck_UID:
	@if [ \`id -u\` = "0" ]; then \\
	  echo "--------------------------------------------------"; \\
	  echo "You cannot run this makefile from the root account"; \\
	  echo "--------------------------------------------------"; \\
	  exit 1; \\
	fi

ck_terminal:
	@stty size | ( read L C; \\
	if (( L < 24 )) || (( C < 80 )) ; then \\
	  echo "--------------------------------------------------"; \\
	  echo "Terminal too small: \$\$C columns x \$\$L lines";\\
	  echo "Minimum: 80 columns x 24 lines";\\
	  echo "--------------------------------------------------"; \\
	  exit 1; \\
	fi )

mk_SETUP:
	@\$(call echo_SU_request)
	@sudo make check-luser
	@sudo make BREAKPOINT=\$(BREAKPOINT) SETUP
	@touch \$@

mk_LUSER: mk_SETUP
	@\$(call echo_SULUSER_request)
	@\$(SU_LUSER) "make -C \$(MOUNT_PT)/\$(SCRIPT_ROOT) BREAKPOINT=\$(BREAKPOINT) LUSER"
	@touch \$@

mk_SUDO: mk_LUSER
	@sudo rm -f envars
	@sudo make BREAKPOINT=\$(BREAKPOINT) SUDO
	@touch \$@

mk_CHROOT: mk_SUDO devices
	@sudo make remove-luser
	@\$(call echo_CHROOT_request)
	@( sudo \$(CHROOT1) -c "cd \$(SCRIPT_ROOT) && make BREAKPOINT=\$(BREAKPOINT) CHROOT")
	@touch \$@

mk_BOOT: mk_CHROOT devices
	@\$(call echo_CHROOT_request)
	@( sudo \$(CHROOT1) -c "cd \$(SCRIPT_ROOT) && make BREAKPOINT=\$(BREAKPOINT) BOOT")
	@touch \$@

mk_BLFS_TOOL: create-sbu_du-report devices
	@if [ "\$(ADD_BLFS_TOOLS)" = "y" ]; then \\
	  \$(call sh_echo_PHASE,Building BLFS_TOOL); \\
	  (sudo \$(CHROOT1) -c "make -C $BLFS_ROOT/work"); \\
	fi;
	@touch \$@

mk_CUSTOM_TOOLS: mk_BLFS_TOOL devices
	@if [ "\$(ADD_CUSTOM_TOOLS)" = "y" ]; then \\
	  \$(call sh_echo_PHASE,Building CUSTOM_TOOLS); \\
	  sudo mkdir -p ${BUILDDIR}${TRACKING_DIR}; \\
	  (sudo \$(CHROOT1) -c "cd \$(SCRIPT_ROOT) && make BREAKPOINT=\$(BREAKPOINT) CUSTOM_TOOLS"); \\
	fi;
	@touch \$@

devices: ck_UID
	sudo env LFS=\$(MOUNT_PT) kernfs-scripts/devices.sh
EOF
) >> $MKFILE
# With systemd, the commands in chapter 9 do not create a
# valid /etc/resolv.conf, so that if we want to enter chroot,
# and systemd has not yet been run (otherwise /etc/resolv.conf
# exists), we just copy resolv.conf from the host.
if [ "$INITSYS" = systemd ]; then
(
    cat << EOF
	if ! [ -e \$(MOUNT_PT)/etc/resolv.conf ]; then \\
	  sudo cp -v /etc/resolv.conf \$(MOUNT_PT)/etc; \\
	  sudo touch \$(MOUNT_PT)/etc/.host-resolvconf; \\
	fi
EOF
) >> $MKFILE
fi
(
    cat << EOF

teardown:
	sudo env LFS=\$(MOUNT_PT) kernfs-scripts/teardown.sh
EOF
) >> $MKFILE
# With systemd, the commands in chapter 9 do not create a
# valid /etc/resolv.conf, so that if we want to enter chroot,
# and systemd has not yet been run (otherwise /etc/resolv.conf
# exists), we just copy resolv.conf from the host.
# We need to remove it now, if it has been created.
if [ "$INITSYS" = systemd ]; then
(
    cat << EOF
	if [ -e \$(MOUNT_PT)/etc/.host-resolvconf ]; then \\
	  sudo rm -v \$(MOUNT_PT)/etc/resolv.conf; \\
	  sudo rm -v \$(MOUNT_PT)/etc/.host-resolvconf; \\
	fi
EOF
) >> $MKFILE
fi
(
    cat << EOF

chroot1: devices
	-sudo \$(CHROOT1)
	\$(MAKE) teardown

chroot: devices
	-sudo \$(CHROOT1)
	\$(MAKE) teardown

SETUP:        $SETUP_TGT
LUSER:        $LUSER_TGT
SUDO:         $SUDO_TGT
EOF
) >> $MKFILE
# With systemd, the commands in chapter 9 do not create a
# valid /etc/resolv.conf, so that if blfs_tools are installed, and
# make-ca is run, it cannot connect. We just copy resolv.conf
# from the host. We'll remove it at the end.
if [ "$INITSYS" = systemd ]; then
(
    cat << EOF
	@cp -v /etc/resolv.conf \$(MOUNT_PT)/etc

EOF
) >> $MKFILE
fi
(
    cat << EOF
CHROOT:       SHELL=\$(filter %bash,\$(CHROOT1))
CHROOT:       $CHROOT_TGT
BOOT:         $BOOT_TGT
CUSTOM_TOOLS: $custom_list

create-sbu_du-report:  mk_BOOT
	@\$(call echo_message, Building)
	@if [ "\$(ADD_REPORT)" = "y" ]; then \\
	  sudo ./create-sbu_du-report.sh logs $VERSION $(date --iso-8601); \\
	  \$(call echo_report,$VERSION-SBU_DU-$(date --iso-8601).report); \\
	fi
	@touch  \$@

check-luser:
	@if grep -q '^\$(LUSER):' /etc/passwd; then \\
	    echo \$(RED)User \$(LUSER) exists:\$(OFF); \\
	    echo This is an error since the LFS book shall create it; \\
	    exit 1; \\
	fi

remove-luser:
	-@userdel \$(LUSER); groupdel \$(LGROUP)
	@rm -rf \$(LUSER_HOME)

ck_mountpoint:
	@if ! mountpoint -q \$(MOUNT_PT); then \\
	   echo \$(RED)"**" \$(MOUNT_PT) is not a mountpoint. "**"\$(OFF); \\
	   echo If this is what you want, just wait. Otherwise, hit; \\
	   echo the \\<return\\> key within 5 seconds and fix your; \\
	   echo configuration.; \\
	   if read -t 5; then exit 1; fi; \\
	fi

do_housekeeping:
	@-rm -f /tools

.PHONY: ck_mountpoint
EOF
) >> $MKFILE

  # Bring over the items from the Makefile.tmp
  cat $MKFILE.tmp >> $MKFILE
  rm $MKFILE.tmp
  echo "Creating Makefile... ${BOLD}DONE${OFF}"
}
