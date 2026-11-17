#!/usr/bin/env python3
"""No third-party dependencies required; invoked before downloading the SDK."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def config(relative_path: str):
    path = ROOT / relative_path
    if not path.is_file():
        raise SystemExit(f"MISSING FILE: {relative_path}")
    # The bundled JSON5 config files do not use any JSON5-only syntax.
    return json.loads(path.read_text(encoding="utf-8"))


project = config("build-profile.json5")
hvigor = config("hvigor/hvigor-config.json5")
app = config("AppScope/app.json5")
module = config("entry/src/main/module.json5")
config("oh-package.json5")
config("entry/oh-package.json5")

products = project["app"].get("products", [])
assert len(products) == 1 and products[0]["name"] == "default"
assert products[0]["compileSdkVersion"] == "26.0.0"
assert products[0]["targetSdkVersion"] == "26.0.0"
assert hvigor["modelVersion"] == "26.0.0"
assert "signingConfigs" not in project["app"], "Do not commit local signing credentials"
assert "signingConfig" not in products[0], "Do not commit local signing configs"
assert app["app"]["bundleName"]
assert module["module"]["mainElement"] == "EntryAbility"
assert (ROOT / "entry/src/main/ets/entryability/EntryAbility.ets").is_file()
assert (ROOT / "entry/src/main/ets/pages/Index.ets").is_file()
assert (ROOT / "AppScope/resources/base/media/app_icon.png").is_file()
assert (ROOT / "entry/src/main/resources/base/media/app_icon.png").is_file()
print("OK: HarmonyOS API 26 project, source files and signing-free CI config are valid.")
