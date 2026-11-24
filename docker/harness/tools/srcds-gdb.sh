#!/bin/bash
# srcds_run -binary: runs srcds_linux (or $SRCDS_BINARY, e.g. ./srcds_linux64 for srcds_run_64)
# under gdb (batch mode), so a crash leaves a report:
# backtraces of all threads, registers, the instructions at the crash and the loaded libraries,
# written to $CRASH_LOG (default /out/crash.txt). Exits with the server's exit status, or 139
# after a crash. Installed into the harness image by docker/harness/Dockerfile.
CRASH_LOG=${CRASH_LOG:-/out/crash.txt}
commands=$(mktemp)
cat > "$commands" <<GDB
set pagination off
set confirm off
set print thread-events off
set print inferior-events off
handle SIGPIPE SIGALRM SIGCHLD SIGUSR1 SIGUSR2 SIG32 SIG33 SIG34 SIG35 nostop noprint pass
run
if \$_isvoid(\$_exitcode)
  set logging file $CRASH_LOG
  set logging overwrite on
  set logging redirect off
  set logging enabled on
  echo ==== srcds crashed ====\n
  info program
  echo \n==== backtrace (crashing thread) ====\n
  bt 40
  echo \n==== registers ====\n
  info registers
  echo \n==== instructions at the crash ====\n
  x/12i \$pc
  echo \n==== all threads ====\n
  thread apply all bt 25
  echo \n==== shared libraries ====\n
  info sharedlibrary
  set logging enabled off
  kill
  quit 139
end
quit \$_exitcode
GDB
gdb -q -batch -x "$commands" --args "${SRCDS_BINARY:-./srcds_linux}" "$@"
rc=$?
rm -f "$commands"
exit $rc
