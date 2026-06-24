# Native Messaging Spike

Goal: validate Chrome MV3 `connectNative()` with the GestureKit host shim.

Manual setup:

1. Build the host with `swift build`.
2. Replace the manifest `path` with the absolute `.build/debug/GestureKitHost` path.
3. Replace `REPLACE_WITH_LOCAL_EXTENSION_ID` with the unpacked extension ID.
4. Install the manifest into Chrome's native messaging host directory for local testing.
5. Load the Chrome extension from `extensions/chrome`.
6. Confirm the extension receives the `hello` message.

The checked-in manifest is a template. It must not contain a machine-specific path or real extension ID.
