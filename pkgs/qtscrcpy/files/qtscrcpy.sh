#!/bin/sh
# QtScrcpy resolves its data files from argv[0], so always start it by full path.
export QTSCRCPY_ADB_PATH="${QTSCRCPY_ADB_PATH:-/usr/bin/adb}"
export QTSCRCPY_SERVER_PATH="${QTSCRCPY_SERVER_PATH:-/usr/lib/qtscrcpy/scrcpy-server}"
exec /usr/lib/qtscrcpy/QtScrcpy "$@"
