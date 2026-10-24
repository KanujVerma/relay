#!/usr/bin/env python3
"""Portable resource-only adapter for the frozen b270 stock product builder.

Requires an independently approved heavy-job slot and existing verified inputs.
Receipts can contain private paths; keep them local and review before sharing.
This public path-parameterized variant did not create the recorded artifact.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

SOURCE = WORK = SCRATCH = CACHE = MODULES = RECEIPT = TEMPORARY_ROOT = None
COMMIT = 'b270297653f78201b56a7c5e57cc2efc322eef61'


def record(value):
    with RECEIPT.open('a') as handle:
        handle.write(json.dumps({'time': time.time(), **value}, sort_keys=True) + '\n')


def budget(phase):
    paths = sorted(str(p) for p in TEMPORARY_ROOT.iterdir() if p.name.lower().startswith('relay'))
    result = subprocess.run(['du', '-sk', *paths], capture_output=True, text=True, check=True)
    allocated = sum(int(line.split('\t', 1)[0]) for line in result.stdout.splitlines()) / 2**20
    disk = os.statvfs(TEMPORARY_ROOT)
    free = disk.f_bavail * disk.f_frsize / 2**30
    record({'phase': phase, 'aggregateRelayGiB': allocated, 'freeGiB': free})
    if allocated > 25 or free < 30:
        raise SystemExit('Resource budget crossed; do not continue dependent heavy work')
    return allocated, free


def main():
    global SOURCE, WORK, SCRATCH, CACHE, MODULES, RECEIPT, TEMPORARY_ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'work', 'scratch', 'cache', 'modules', 'receipt', 'temporary-root'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    SOURCE, WORK, SCRATCH, CACHE, MODULES, RECEIPT, TEMPORARY_ROOT = (
        args.source.resolve(), args.work.resolve(), args.scratch.resolve(),
        args.cache.resolve(), args.modules.resolve(), args.receipt.resolve(),
        args.temporary_root.resolve())
    if subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD']).decode().strip() != COMMIT:
        raise SystemExit('Frozen source changed')
    if subprocess.check_output(['git', '-C', str(SOURCE), 'status', '--porcelain']):
        raise SystemExit('Frozen source is dirty')
    for path in (WORK/'venv', WORK/'interpreter', WORK/'cpython-3.14.9-20261021-arm64.tar.gz',
                 WORK/'cpython-3.14.9-20261021-full.tar.zst', SCRATCH, CACHE, MODULES):
        if not path.exists():
            raise SystemExit(f'Required retained input is absent: {path}')
    record({'phase': 'source', 'sourceCommit': COMMIT})
    allocated, free = budget('before-stock-builder')
    if allocated + 2.5 > 25 or free - 2.5 < 30:
        raise SystemExit('The reviewed 2.5 GiB peak allowance no longer fits')
    record({'phase': 'projection', 'additionalPeakAllowanceGiB': 2.5,
            'projectedAggregateGiB': allocated + 2.5, 'projectedFreeGiB': free - 2.5})
    spec = importlib.util.spec_from_file_location('frozen_product_builder', SOURCE/'packaging/build_product.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    installed = json.loads(subprocess.check_output([str(WORK/'venv/bin/python'), '-I', '-c',
        "import importlib.metadata,json;print(json.dumps({d.metadata['Name'].lower().replace('_','-'):d.version for d in importlib.metadata.distributions()}))"]))
    expected = builder.lock_versions()
    if any(installed.get(name) != version for name, version in expected.items()) or set(installed)-set(expected)-{'pip'}:
        raise SystemExit('Preserved build environment is not already complete; no install is authorized')
    record({'phase': 'complete-existing-environment', 'lockedPackages': len(expected)})
    original_environment, original_run = builder.build_environment, builder.run

    def environment(work, parent):
        value = original_environment(work, parent)
        value.update(CLANG_MODULE_CACHE_PATH=str(MODULES), SWIFTPM_MODULECACHE_OVERRIDE=str(MODULES))
        return value

    def run(arguments, *, env=None, capture=False):
        values = [str(value) for value in arguments]
        if values[0] == 'swift':
            values[values.index('--jobs')+1] = '2'
            values[values.index('--cache-path')+1] = str(CACHE)
        heavy = ('PyInstaller' in values or values[0] == 'swift' and '--show-bin-path' not in values
                 or 'test_product_runtime_bundle.py' in values)
        if heavy:
            budget('before-command')
        record({'argv': values, 'resourceEnvironment': {key: env[key] for key in
                ('CLANG_MODULE_CACHE_PATH', 'SWIFTPM_MODULECACHE_OVERRIDE', 'PYINSTALLER_CONFIG_DIR') if env and key in env}})
        result = original_run(values, env=env, capture=capture)
        if heavy:
            budget('after-command')
        return result

    builder.build_environment, builder.run = environment, run
    # Stock prepare/locks/archive hashes/notices/freezer/provenance/assembly,
    # Mach-O audits, signatures and smoke tests all execute without substitution.
    sys.argv = [str(SOURCE/'packaging/build_product.py'), '--work-root', str(WORK),
                '--native-scratch', str(SCRATCH), '--offline', '--configuration', 'release',
                '--output', str(WORK/'Relay.app')]
    builder.main()
    budget('completed-stock-builder')


if __name__ == '__main__':
    main()
