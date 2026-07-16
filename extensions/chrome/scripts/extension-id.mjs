import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const extensionIDCharacter = (hex) => String.fromCharCode("a".charCodeAt(0) + Number.parseInt(hex, 16));

export function extensionIDFromPublicKey(publicKey) {
  if (typeof publicKey !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(publicKey)) {
    throw new Error("invalid extension public key");
  }

  const decoded = Buffer.from(publicKey, "base64");
  const normalized = decoded.toString("base64").replace(/=+$/, "");
  if (decoded.length === 0 || normalized !== publicKey.replace(/=+$/, "")) {
    throw new Error("invalid extension public key");
  }

  return createHash("sha256")
    .update(decoded)
    .digest("hex")
    .slice(0, 32)
    .split("")
    .map(extensionIDCharacter)
    .join("");
}

export function extensionIDFromManifest(manifest) {
  if (manifest === null || typeof manifest !== "object" || !("key" in manifest)) {
    throw new Error("missing extension public key");
  }
  return extensionIDFromPublicKey(manifest.key);
}

function parseArguments(argumentsList) {
  if (argumentsList.length === 0) {
    return resolve(fileURLToPath(new URL("../manifest.json", import.meta.url)));
  }
  if (argumentsList.length === 2 && argumentsList[0] === "--manifest") {
    return resolve(argumentsList[1]);
  }
  throw new Error("usage: extension-id.mjs [--manifest <path>]");
}

async function main() {
  const manifestPath = parseArguments(process.argv.slice(2));
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  process.stdout.write(`${extensionIDFromManifest(manifest)}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
