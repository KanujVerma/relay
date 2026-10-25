from hashlib import sha256
from importlib.util import module_from_spec, spec_from_file_location
from io import BytesIO
from pathlib import Path
import tarfile
import os
import tempfile
import unittest
from unittest.mock import patch


class ProductPackagingTests(unittest.TestCase):
    def setUp(self):
        source=Path(__file__).resolve().parents[1]/"packaging/build_product.py"
        spec=spec_from_file_location("relay_packaging_test",source)
        self.module=module_from_spec(spec);spec.loader.exec_module(self.module)

    def test_wrong_hash_cannot_extract_or_create_an_interpreter(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);archive=root/"input.tar.gz";archive.write_bytes(b"not an archive")
            with self.assertRaises(ValueError):
                self.module.extract_verified(archive,root/"interpreter",size=14,digest="0"*64)
            self.assertFalse((root/"interpreter").exists())

    def test_verified_archive_cannot_write_outside_its_build_directory(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);archive=root/"input.tar.gz"
            with tarfile.open(archive,"w:gz") as output:
                item=tarfile.TarInfo("../escape");item.size=3;output.addfile(item,BytesIO(b"abc"))
            with self.assertRaises((ValueError,tarfile.TarError)):
                self.module.extract_verified(archive,root/"interpreter",size=archive.stat().st_size,digest=sha256(archive.read_bytes()).hexdigest())
            self.assertFalse((root/"escape").exists())

    def test_native_load_parser_distinguishes_dependency_id_rpath_and_minimum_os(self):
        output="""Load command 0
          cmd LC_ID_DYLIB
         name @rpath/libsample.dylib (offset 24)
Load command 1
          cmd LC_LOAD_DYLIB
         name @loader_path/libpython3.14.dylib (offset 24)
Load command 2
          cmd LC_RPATH
         path /private/tmp/obsolete-build (offset 12)
Load command 3
          cmd LC_BUILD_VERSION
        minos 14.0
"""
        dependencies,rpaths,minimum=self.module.load_commands(output)
        self.assertEqual(dependencies,["@loader_path/libpython3.14.dylib"])
        self.assertEqual(rpaths,["/private/tmp/obsolete-build"]);self.assertEqual(minimum,(14,0))

    def test_native_audit_uses_canonical_internal_code_and_rejects_external_symlinks(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);bundle=root/"bundle";bundle.mkdir();library=bundle/"nested/code";library.parent.mkdir()
            library.write_bytes(b"\xcf\xfa\xed\xfe")
            (bundle/"alias").symlink_to("nested/code")
            self.assertEqual(list(self.module.macho_files(bundle)),[library.resolve()])
            outside=root/"unrelated-code";outside.write_bytes(b"\xcf\xfa\xed\xfe")
            (bundle/"escape").symlink_to(outside)
            with self.assertRaises(ValueError): list(self.module.macho_files(bundle))

    def test_build_environment_does_not_inherit_python_paths_or_private_pip_sources(self):
        with tempfile.TemporaryDirectory() as name:
            value=self.module.build_environment(Path(name),{"PATH":"/usr/bin:/bin","PYTHONPATH":"/synthetic/private",
                "PYTHONHOME":"/synthetic/private","VIRTUAL_ENV":"/synthetic/private",
                "PIP_INDEX_URL":"https://synthetic.invalid/private","PIP_EXTRA_INDEX_URL":"https://synthetic.invalid/extra",
                "PIP_CONFIG_FILE":"/synthetic/private/config"})
            for key in ("PYTHONPATH","PYTHONHOME","VIRTUAL_ENV","PIP_INDEX_URL","PIP_EXTRA_INDEX_URL"):self.assertNotIn(key,value)
            self.assertEqual(value["PIP_CONFIG_FILE"],os.devnull);self.assertEqual(value["PATH"],"/usr/bin:/bin")

    def test_explicit_retained_module_caches_are_preserved_without_creating_defaults(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);work=root/"work";modules=root/"Retained Modules"
            modules.mkdir()
            value=self.module.build_environment(work,{"CLANG_MODULE_CACHE_PATH":str(modules),
                "SWIFTPM_MODULECACHE_OVERRIDE":str(modules)})
            self.assertEqual(value["CLANG_MODULE_CACHE_PATH"],str(modules))
            self.assertEqual(value["SWIFTPM_MODULECACHE_OVERRIDE"],str(modules))
            self.assertFalse(work.exists())

    def test_retained_swift_cache_reaches_real_stock_build_command_before_any_assembly(self):
        class CapturedNativeLaunch(Exception):pass
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);cache=root/"Retained Swift Cache";cache.mkdir();commands=[]
            def capture(arguments,**_):
                commands.append([str(item) for item in arguments]);raise CapturedNativeLaunch()
            with patch.object(self.module,"run",side_effect=capture),self.assertRaises(CapturedNativeLaunch):
                self.module.assemble(root,root/"helper",root/"native",{"RELAY_BUILD_SWIFT_CACHE":str(cache)},root/"Relay.app","release")
            self.assertEqual(len(commands),1)
            self.assertEqual(commands[0][commands[0].index("--cache-path")+1],str(cache))
            self.assertEqual(commands[0][commands[0].index("--jobs")+1],"2")
            self.assertFalse((root/"Relay.staging.app").exists())

    def test_native_history_resource_copy_contains_actual_grdb_privacy_bundle_and_license(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);binary=root/"native";resources=root/"Resources";resources.mkdir()
            for bundle in ("KeyboardShortcuts_KeyboardShortcuts.bundle","FluidAudio_LuxTtsG2pResources.bundle","GRDB_GRDB.bundle"):
                folder=binary/bundle;folder.mkdir(parents=True);(folder/"fixture.txt").write_text(bundle)
            (binary/"GRDB_GRDB.bundle/PrivacyInfo.xcprivacy").write_text("synthetic privacy manifest")
            self.module.copy_native_resources(binary,resources)
            self.assertEqual((resources/"GRDB_GRDB.bundle/PrivacyInfo.xcprivacy").read_text(),"synthetic privacy manifest")
            notice=(resources/"RelayNativeNotices.txt").read_text()
            self.assertIn("b83108d10f42680d78f23fe4d4d80fc88dab3212",notice)
            self.assertIn("Copyright (C) 2015-2025 Gwendal Roué",notice)
            self.assertIn("Permission is hereby granted",notice)


if __name__=="__main__":unittest.main()
