#!/bin/bash

set -x

DUMPFILE=/tmp/pg.$(date +%Y.%m.%d-%H.%M.%S).dump
PGPASSWORD=postgres pg_dumpall -h postgres -p 5432  -U postgres  > $DUMPFILE
zstd --no-progress $DUMPFILE
ccencrypt -K password ${DUMPFILE}.zst

ls -lh /tmp/pg.*

echo b2 bucket info - $B2BUCKET $B2KEYID
set +x
backblaze-b2 authorize-account $B2KEYID $B2KEYSECRET

set -x
backblaze-b2 upload-file --noProgress $B2BUCKET ${DUMPFILE}.zst.cpt ${DUMPFILE}.zst.cpt 

exit 0