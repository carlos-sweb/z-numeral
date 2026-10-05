#!/usr/bin/env python3
"""Compile README Zig examples and verify local-package installation offline."""
from pathlib import Path
import re
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache' / 'docs'
CACHE.mkdir(parents=True, exist_ok=True)
blocks = re.findall(r'```zig\n(.*?)\n```', (ROOT / 'README.md').read_text(), re.S)
examples = []
manifest_fragment = None
build_fragment = None
for block in blocks:
    if block.startswith('.z_numeral ='):
        manifest_fragment = block
    elif 'b.dependency(' in block:
        build_fragment = block
    else:
        examples.append(block)
assert manifest_fragment and build_fragment, 'Installation examples missing'
source = 'const std = @import("std");\nconst numeral = @import("numeral");\n'
for i, block in enumerate(examples, 1):
    source += f'test "README example {i}" {{\n{block}\n}}\n'
(CACHE / 'examples.zig').write_text(source)
subprocess.run(['zig', 'test', '--dep', 'numeral', f'-Mroot={CACHE / "examples.zig"}',
                f'-Mnumeral={ROOT / "src/root.zig"}'], cwd=ROOT, check=True)
consumer = CACHE / 'consumer'
consumer.mkdir(exist_ok=True)
(consumer / 'main.zig').write_text('const numeral = @import("numeral");\npub fn main() !void { var b: [32]u8 = undefined; _ = try numeral.formatBuf(&b, 42, .{}); }\n')
(consumer / 'build.zig').write_text('''const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{ .name = "consumer", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize }) });
''' + build_fragment + '\n b.installArtifact(exe);\n}\n')
fragment = manifest_fragment.replace('../z-numeral', os.path.relpath(ROOT, consumer).replace(os.sep, '/'))
manifest = '.{ .name = .z_numeral_docs, .fingerprint = 0x11111111ca6f7933, .version = "0.0.0", .minimum_zig_version = "0.16.0", .dependencies = .{ ' + fragment + ' }, .paths = .{ "" } }\n'
(consumer / 'build.zig.zon').write_text(manifest)
# The compiler validates the name-derived fingerprint. Bootstrap its prefix
# once for this disposable consumer; the package fingerprint stays unchanged.
probe = subprocess.run(['zig', 'build'], cwd=consumer, text=True, capture_output=True)
if probe.returncode:
    suggestion = re.search(r'use this value: (0x[0-9a-f]+)', probe.stderr)
    if not suggestion:
        raise RuntimeError(probe.stderr)
    manifest = manifest.replace('0x11111111ca6f7933', suggestion.group(1))
    (consumer / 'build.zig.zon').write_text(manifest)
    subprocess.run(['zig', 'build'], cwd=consumer, check=True)
print(f'{len(examples)} README examples and package installation verified')
