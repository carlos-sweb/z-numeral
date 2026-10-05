#!/usr/bin/env python3
"""Compile README examples and verify package installation locally or from the pinned URL."""
from pathlib import Path
import argparse
import re
import os
import subprocess
import shlex

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--remote', action='store_true', help='Run the README zig fetch --save command instead of using a local checkout')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache' / 'docs'
CACHE.mkdir(parents=True, exist_ok=True)
blocks = re.findall(r'```zig\n(.*?)\n```', (ROOT / 'README.md').read_text(), re.S)
examples = []
build_fragment = None
for block in blocks:
    if 'b.dependency(' in block:
        build_fragment = block
    else:
        examples.append(block)
readme = (ROOT / 'README.md').read_text()
fetch_command = re.search(r'^zig fetch --save=z_numeral \S+$', readme, re.M)
assert fetch_command and build_fragment, 'Installation examples missing'
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
manifest = (ROOT / 'examples/consumer/build.zig.zon').read_text()
dependency = r'\.z_numeral = \.\{.*?\},'
if args.remote:
    manifest, replacements = re.subn(dependency, '', manifest, count=1, flags=re.S)
else:
    # Keep normal documentation checks offline while testing the current source.
    local_path = os.path.relpath(ROOT, consumer).replace(os.sep, '/')
    manifest, replacements = re.subn(
        dependency, lambda _: f'.z_numeral = .{{ .path = "{local_path}" }},',
        manifest, count=1, flags=re.S)
assert replacements == 1, 'Consumer dependency missing'
(consumer / 'build.zig.zon').write_text(manifest)
if args.remote:
    subprocess.run(shlex.split(fetch_command.group(0)), cwd=consumer, check=True)
subprocess.run(['zig', 'build'], cwd=consumer, check=True)
mode = 'pinned URL/hash' if args.remote else 'local checkout'
print(f'{len(examples)} README examples and package installation verified ({mode})')
