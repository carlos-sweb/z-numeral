#!/usr/bin/env python3
"""Compile README examples and verify package installation locally or from cache."""
from pathlib import Path
import argparse
import re
import os
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--remote', action='store_true', help='Use the pinned URL/hash instead of a local checkout; private packages must be cached first')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache' / 'docs'
CACHE.mkdir(parents=True, exist_ok=True)
blocks = re.findall(r'```zig\n(.*?)\n```', (ROOT / 'README.md').read_text(), re.S)
examples = []
manifest_fragment = None
build_fragment = None
for block in blocks:
    if block.startswith('.{') and '.dependencies' in block:
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
assert manifest_fragment.strip() == (ROOT / 'examples/consumer/build.zig.zon').read_text().strip(), 'README manifest differs from the standalone consumer'
manifest = manifest_fragment
if not args.remote:
    # Keep normal documentation checks offline while testing the current source.
    local_path = os.path.relpath(ROOT, consumer).replace(os.sep, '/')
    manifest, replacements = re.subn(
        r'\.url = "[^"\n]+",\s*\.hash = "[^"\n]+",',
        lambda _: f'.path = "{local_path}",', manifest, count=1)
    assert replacements == 1, 'Remote dependency URL/hash missing'
(consumer / 'build.zig.zon').write_text(manifest + '\n')
subprocess.run(['zig', 'build'], cwd=consumer, check=True)
mode = 'pinned URL/hash' if args.remote else 'local checkout'
print(f'{len(examples)} README examples and package installation verified ({mode})')
