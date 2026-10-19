#!/usr/bin/env bash
# Builds a Developer ID signed, notarized and stapled ReBezel.app, plus a DMG and a zip.
# Given a version, it also publishes them: bumps the version, signs the zip for Sparkle,
# adds it to appcast.xml, commits and tags the release and creates the GitHub release.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in the keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials stored under a keychain profile (uses an app-specific password):
#        xcrun notarytool store-credentials rebezel-notary --apple-id <apple-id> --team-id SPRLQ9JET8
#   3. For publishing: the Sparkle EdDSA key in the keychain (its public half is SUPublicEDKey
#      in project.yml), `gh auth login`, and a public GitHub repo.
#
# Usage:
#   Scripts/release.sh 1.2.0   # build and publish 1.2.0; needs release-notes/1.2.0.md
#   Scripts/release.sh         # build the current version only, nothing is changed or published
#   NOTARY_PROFILE=other-profile Scripts/release.sh
#   SKIP_NOTARIZE=1 Scripts/release.sh   # sign only, for a quick local check
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/release.sh
set -euo pipefail

APP_NAME="ReBezel"
TEAM_ID="SPRLQ9JET8"
GITHUB_REPO="Elhoej/ReBezel"
NOTARY_PROFILE="${NOTARY_PROFILE:-rebezel-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
NEW_VERSION="${1:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"
# Outside BUILD_DIR so packages are not downloaded again on every run.
PACKAGES_DIR="$ROOT/build/SourcePackages"
SPARKLE_BIN="$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"
APPCAST="$ROOT/appcast.xml"
APPCAST_MARKER="inserts new items below this line"
# Files the version bump and appcast update touch; restored if publishing fails.
RELEASE_FILES=(project.yml "$APP_NAME.xcodeproj" "$APP_NAME/Info.plist" appcast.xml)

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Submits a file for notarization, waits, and fails with Apple's log if it is not accepted.
notarize() {
    local file="$1" result status id
    result="$BUILD_DIR/notary-$(basename "$file").json"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$result" || true
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    if [[ "$status" != "Accepted" ]]; then
        cat "$result" >&2
        id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fi
        fail "notarization of $(basename "$file") finished with status: $status"
    fi
    echo "Notarization accepted."
}

# Undoes the version bump and appcast change unless the release commit was made.
RESTORE_ON_EXIT=0
restore() {
    if [[ "$RESTORE_ON_EXIT" == "1" ]]; then
        echo "Restoring ${RELEASE_FILES[*]}"
        git -C "$ROOT" checkout -- "${RELEASE_FILES[@]}" || true
    fi
}
trap restore EXIT

cd "$ROOT"

PUBLISH=0
[[ -n "$NEW_VERSION" ]] && PUBLISH=1

step "Preflight"
# xcodebuild needs a full Xcode; fall back to one in /Applications if xcode-select
# points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    XCODE="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "$XCODE" ]] || fail "xcodebuild needs Xcode; set DEVELOPER_DIR to its Contents/Developer."
    export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi
echo "Xcode: $(xcodebuild -version | head -1) at ${DEVELOPER_DIR:-$(xcode-select -p)}"
IDENTITY="$(security find-identity -v -p codesigning \
    | grep -o "\"Developer ID Application: [^\"]*($TEAM_ID)\"" | head -1 | tr -d '"' || true)"
[[ -n "$IDENTITY" ]] || fail "no 'Developer ID Application' certificate for team $TEAM_ID in the keychain."
echo "Signing identity: $IDENTITY"
if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || fail "no working notarization credentials in keychain profile '$NOTARY_PROFILE'; run:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID"
fi

xcodebuild -resolvePackageDependencies -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" -quiet

if [[ "$PUBLISH" == "1" ]]; then
    TAG="v$NEW_VERSION"
    NOTES="$ROOT/release-notes/$NEW_VERSION.md"
    echo "Publishing $TAG"

    [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the version must look like 1.2.3, got '$NEW_VERSION'."
    [[ "$SKIP_NOTARIZE" != "1" ]] || fail "SKIP_NOTARIZE=1 can't be used when publishing."
    command -v xcodegen >/dev/null || fail "xcodegen is needed to apply the version bump (brew install xcodegen)."
    gh auth status >/dev/null 2>&1 || fail "gh is not logged in; run 'gh auth login'."
    [[ "$(gh repo view "$GITHUB_REPO" --json visibility -q .visibility)" == "PUBLIC" ]] \
        || fail "$GITHUB_REPO is not public, so users could not download the update."

    [[ "$(git branch --show-current)" == "main" ]] || fail "publishing only happens from main."
    [[ -z "$(git status --porcelain)" ]] || fail "commit or stash your changes before publishing."
    git fetch --quiet origin main
    git merge-base --is-ancestor origin/main HEAD || fail "main is behind origin/main; pull first."
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag $TAG already exists locally."
    [[ -z "$(git ls-remote --tags origin "refs/tags/$TAG")" ]] || fail "tag $TAG already exists on origin."

    [[ -s "$NOTES" ]] || fail "write the release notes in release-notes/$NEW_VERSION.md (Markdown) and commit them."
    ! grep -q ']]>' "$NOTES" || fail "release notes can't contain ']]>' (it ends the appcast's CDATA)."
    grep -q "$APPCAST_MARKER" "$APPCAST" || fail "appcast.xml is missing the '$APPCAST_MARKER' comment."

    PLIST_KEY="$(sed -nE 's/^ *SUPublicEDKey: *"?([^"]*)"?$/\1/p' project.yml)"
    KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
    [[ -n "$KEYCHAIN_KEY" ]] || fail "no Sparkle signing key in the keychain (see README → Releasing)."
    [[ "$PLIST_KEY" == "$KEYCHAIN_KEY" ]] \
        || fail "SUPublicEDKey in project.yml ($PLIST_KEY) doesn't match the keychain's key ($KEYCHAIN_KEY)."

    OLD_BUILD="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?$/\1/p' project.yml)"
    [[ -n "$OLD_BUILD" ]] || fail "couldn't read CURRENT_PROJECT_VERSION from project.yml."
    NEW_BUILD=$((OLD_BUILD + 1))
    FEED_BUILD="$(sed -nE 's/.*<sparkle:version>([0-9]+)<.*/\1/p' "$APPCAST" | sort -n | tail -1)"
    (( NEW_BUILD > ${FEED_BUILD:-0} )) \
        || fail "build $NEW_BUILD is not newer than build $FEED_BUILD in appcast.xml; raise CURRENT_PROJECT_VERSION."

    step "Setting version $NEW_VERSION ($NEW_BUILD)"
    RESTORE_ON_EXIT=1
    sed -i '' -E \
        -e "s/^( *MARKETING_VERSION: *).*/\1\"$NEW_VERSION\"/" \
        -e "s/^( *CURRENT_PROJECT_VERSION: *).*/\1\"$NEW_BUILD\"/" \
        project.yml
    xcodegen generate --quiet
elif [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: the working tree has uncommitted changes; they will be part of this build."
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

step "Archiving"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" -archivePath "$ARCHIVE" -quiet archive

step "Exporting with Developer ID"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" -exportPath "$EXPORT_DIR" -quiet

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application"* && "$SIGNATURE" == *"(runtime)"* ]] \
    || fail "exported app is not signed with Developer ID and the hardened runtime."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
echo "Version $VERSION ($BUILD)"
if [[ "$PUBLISH" == "1" ]]; then
    [[ "$VERSION" == "$NEW_VERSION" && "$BUILD" == "$NEW_BUILD" ]] \
        || fail "the app was built as $VERSION ($BUILD), expected $NEW_VERSION ($NEW_BUILD)."
    APP_KEY="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$APP_KEY" == "$KEYCHAIN_KEY" ]] || fail "the built app's SUPublicEDKey doesn't match the keychain's key."
fi

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    step "Notarizing the app"
    ditto -c -k --keepParent "$APP" "$BUILD_DIR/notarize.zip"
    notarize "$BUILD_DIR/notarize.zip"
    rm "$BUILD_DIR/notarize.zip"
    xcrun stapler staple "$APP"
fi

step "Creating DMG"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    step "Notarizing the DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
fi

step "Creating zip"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    step "Gatekeeper check"
    spctl --assess --type execute --verbose=2 "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

if [[ "$PUBLISH" == "1" ]]; then
    step "Adding $VERSION to the appcast"
    # Prints: sparkle:edSignature="…" length="…"
    ENCLOSURE_SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"
    [[ "$ENCLOSURE_SIGNATURE" == *"sparkle:edSignature="* ]] || fail "sign_update failed: $ENCLOSURE_SIGNATURE"
    MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
    ITEM="$BUILD_DIR/appcast-item.xml"
    cat > "$ITEM" <<XML
        <item>
            <title>Version $VERSION</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
            <description sparkle:format="markdown"><![CDATA[
$(cat "$NOTES")
]]></description>
            <enclosure url="https://github.com/$GITHUB_REPO/releases/download/$TAG/$(basename "$ZIP")" type="application/octet-stream" $ENCLOSURE_SIGNATURE/>
        </item>
XML
    awk -v item="$ITEM" -v marker="$APPCAST_MARKER" '
        { print }
        index($0, marker) { while ((getline line < item) > 0) print line }
    ' "$APPCAST" > "$BUILD_DIR/appcast.xml"
    xmllint --noout "$BUILD_DIR/appcast.xml" || fail "the updated appcast is not valid XML."
    cp "$BUILD_DIR/appcast.xml" "$APPCAST"

    step "Publishing $TAG"
    git add "${RELEASE_FILES[@]}"
    git commit --quiet -m "Release $VERSION ($BUILD)"
    git tag -a "$TAG" -m "$APP_NAME $VERSION"
    RESTORE_ON_EXIT=0
    git push --quiet origin "$TAG" \
        || fail "the release commit and tag $TAG were made locally, but pushing the tag failed. Fix it, then
  git push origin $TAG
  gh release create $TAG --repo $GITHUB_REPO --verify-tag --title \"$APP_NAME $VERSION\" --notes-file $NOTES $DMG $ZIP
  git push origin main"
    # The appcast on main goes live last, once the files it points to exist.
    if ! gh release create "$TAG" --repo "$GITHUB_REPO" --verify-tag \
        --title "$APP_NAME $VERSION" --notes-file "$NOTES" "$DMG" "$ZIP"; then
        fail "$TAG is committed and pushed, but the GitHub release failed. Fix it, then run:
  gh release create $TAG --repo $GITHUB_REPO --verify-tag --title \"$APP_NAME $VERSION\" --notes-file $NOTES $DMG $ZIP
  git push origin main"
    fi
    git push --quiet origin main \
        || fail "the GitHub release is up, but pushing main (and so the appcast) failed; run 'git push origin main'."
fi

step "Done"
echo "$DMG"
echo "$ZIP"
if [[ "$PUBLISH" == "1" ]]; then
    echo "https://github.com/$GITHUB_REPO/releases/tag/$TAG"
fi
