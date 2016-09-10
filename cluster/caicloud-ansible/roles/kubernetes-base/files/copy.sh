#!/bin/bash

# Copy files from master by scp command in expect script.
#
# Assumed vars:
#   REMOTE_FILE_NAME
#   REMOTE_USER
#   REMOTE_IP
#   REMOTE_PASSWORD
#   DEST_PATH

expect <<EOF
set timeout -1
spawn scp -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=quiet \
    ${REMOTE_USER}@${REMOTE_IP}:${REMOTE_FILE_NAME} ${DEST_PATH}

expect {
  "*?assword*" {
    send -- "${REMOTE_PASSWORD}\r"
    exp_continue
  }
  "?ommand failed" {exit 1}
  "lost connection" { exit 1 }
  eof {}
}
EOF
