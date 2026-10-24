#!/usr/bin/env node
/**
 * Post-assemble gate for BachataS4 APKs.
 *
 * Checks that the packaged APK contains the managed runtime assets and/or host
 * jniLibs expected by the Android app. Invoked from app/build.gradle.kts as
 * finalize of assemble<Variant>.
 *
 * Usage: node verify-native-fixes.mjs <path-to.apk>
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const apk = resolve(process.argv[2] ?? "");
if (!apk || !existsSync(apk)) {
  console.error("Usage: verify-native-fixes.mjs <app.apk>");
  process.exit(2);
}

function listing(archive) {
  return execFileSync("unzip", ["-Z1", archive], {
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  })
    .split("\n")
    .filter(Boolean);
}

const entries = listing(apk);
const errors = [];

// Managed runtime (preferred path for BachataS4).
const hasManifest = entries.includes("assets/runtime/manifest.json");
const hasRuntimeZip = entries.includes("assets/runtime/runtime.zip");
const jniLibs = entries.filter(
  (e) => e.startsWith("lib/arm64-v8a/") && e.endsWith(".so"),
);

if (!hasManifest && !hasRuntimeZip && jniLibs.length === 0) {
  errors.push(
    "APK has neither assets/runtime/{manifest.json,runtime.zip} nor lib/arm64-v8a/*.so",
  );
}

if (hasManifest !== hasRuntimeZip) {
  errors.push(
    `Incomplete managed runtime: manifest=${hasManifest} runtime.zip=${hasRuntimeZip}`,
  );
}

// Optional host loader — present when package-runtime stages jniLibs.
const hostLoader = "lib/arm64-v8a/libbachata_host_loader.so";
const box64 = "lib/arm64-v8a/libbox64.so";
if (jniLibs.length > 0) {
  const names = jniLibs.map((e) => e.split("/").at(-1));
  console.log(`jniLibs arm64-v8a: ${names.join(", ")}`);
}

if (hasRuntimeZip) {
  // Spot-check nested ZIP for FEX/Box64 host runners when present in package.
  try {
    const nested = execFileSync("unzip", ["-p", apk, "assets/runtime/runtime.zip"], {
      encoding: "buffer",
      maxBuffer: 256 * 1024 * 1024,
    });
    // Write to pipe via unzip -l on a temp approach: list nested via unzip -Z1 after extract is heavy.
    // Instead use unzip -l on the APK member is not supported; extract listing with python-free method:
    const { mkdtempSync, writeFileSync, rmSync } = await import("node:fs");
    const { tmpdir } = await import("node:os");
    const { join } = await import("node:path");
    const dir = mkdtempSync(join(tmpdir(), "bachata-native-fix-"));
    try {
      const zipPath = join(dir, "runtime.zip");
      writeFileSync(zipPath, nested);
      const nestedEntries = listing(zipPath);
      const interesting = [
        "host/box64",
        "host/fexcore-smoke",
        "host/fexcore-guest-harness",
        "host/shadps4-arm64-fex",
        "bin/shadps4",
      ].filter((p) => nestedEntries.includes(p));
      console.log(
        `runtime.zip entries: ${nestedEntries.length}; host runners: ${interesting.join(", ") || "(none)"}`,
      );
      if (interesting.length === 0) {
        errors.push(
          "runtime.zip present but missing expected host runners (box64 / fexcore-smoke / shadps4)",
        );
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  } catch (err) {
    errors.push(`Failed to inspect nested runtime.zip: ${err.message ?? err}`);
  }
}

if (errors.length) {
  console.error(`verify-native-fixes FAILED for ${apk}:\n- ${errors.join("\n- ")}`);
  process.exit(1);
}

console.log(
  `verify-native-fixes OK: ${apk} (manifest=${hasManifest}, runtime.zip=${hasRuntimeZip}, jni=${jniLibs.length})`,
);
