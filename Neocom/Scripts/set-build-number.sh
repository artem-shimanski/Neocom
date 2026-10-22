#!/bin/sh
# Sets CFBundleVersion of the built product to the git commit count.
# On any failure the plist is left untouched (CURRENT_PROJECT_VERSION stays as the fallback).

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
COUNT=$(git -C "${SRCROOT}" rev-list --count HEAD 2>/dev/null)

case "${COUNT}" in
    ''|*[!0-9]*) echo "note: git commit count unavailable, keeping CURRENT_PROJECT_VERSION"; exit 0 ;;
esac

if [ -f "${PLIST}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${COUNT}" "${PLIST}" 2>/dev/null \
        || echo "note: could not set CFBundleVersion, keeping CURRENT_PROJECT_VERSION"
fi
exit 0
