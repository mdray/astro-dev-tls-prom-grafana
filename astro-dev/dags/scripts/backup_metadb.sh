#!/bin/bash

set -x

DUMPFILE=/tmp/pg.$(date +%Y.%m.%d-%H.%M.%S).dump
PGPASSWORD=postgres pg_dumpall -h postgres -p 5432  -U postgres  > $DUMPFILE
zstd --no-progress $DUMPFILE
ccencrypt -K password ${DUMPFILE}.zst

ls -lh /tmp/pg.*

exit 0