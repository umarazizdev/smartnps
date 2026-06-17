#!/bin/sh
set -e

# Flutter native assets embed objective_c.framework (via flutter_secure_storage, etc.)
# but do not copy its dSYM into archives. Xcode 16+ warns during App Store upload.

case "${CONFIGURATION}" in
  Release|Profile) ;;
  *)
    exit 0
    ;;
esac

FRAMEWORK_BINARY="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/objective_c.framework/objective_c"
OUTPUT_DSYM="${DWARF_DSYM_FOLDER_PATH}/objective_c.framework.dSYM"

if [ ! -f "${FRAMEWORK_BINARY}" ]; then
  echo "note: objective_c.framework not embedded; skipping dSYM generation"
  exit 0
fi

echo "Generating dSYM for objective_c.framework -> ${OUTPUT_DSYM}"
/usr/bin/dsymutil "${FRAMEWORK_BINARY}" -o "${OUTPUT_DSYM}"
/usr/bin/dwarfdump --uuid "${OUTPUT_DSYM}"
