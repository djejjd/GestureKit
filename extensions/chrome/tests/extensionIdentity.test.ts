import { describe, expect, it } from "vitest";
import {
  extensionIDFromManifest,
  extensionIDFromPublicKey
} from "../scripts/extension-id.mjs";

describe("extension identity", () => {
  it("derives Chrome's stable a-p extension ID from a public key", () => {
    const publicKey = "AQID";

    expect(extensionIDFromPublicKey(publicKey)).toBe("adjafimgpcmamlejcmfddlakenbeophh");
    expect(extensionIDFromPublicKey(publicKey)).toMatch(/^[a-p]{32}$/);
  });

  it("reads the public key from a manifest without accepting a missing key", () => {
    expect(extensionIDFromManifest({ key: "AQID" })).toBe("adjafimgpcmamlejcmfddlakenbeophh");
    expect(() => extensionIDFromManifest({})).toThrow("missing extension public key");
  });

  it("rejects malformed public key input", () => {
    expect(() => extensionIDFromPublicKey("not valid base64")).toThrow("invalid extension public key");
    expect(() => extensionIDFromPublicKey("")).toThrow("invalid extension public key");
  });
});
