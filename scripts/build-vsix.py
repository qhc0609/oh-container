# -*- coding: utf-8 -*-
"""把一个已安装的 VS Code 扩展目录重新打包成 .vsix，供离线安装用。

为什么需要它：目标机器不能上网，装不了扩展市场里的 Continue。
VS Code 的 `--install-extension xxx.vsix` 是离线的官方安装通道，
但它要求 zip 里有 extension.vsixmanifest 和 [Content_Types].xml，
而已经装好的扩展目录里没有这两个文件（那是安装时被剥掉的）。
所以这里按 VSX 规范补出来。
"""
import io
import json
import os
import sys
import zipfile

CONTENT_TYPES = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".mjs" ContentType="application/javascript"/>
  <Default Extension=".cjs" ContentType="application/javascript"/>
  <Default Extension=".wasm" ContentType="application/wasm"/>
  <Default Extension=".md" ContentType="text/markdown"/>
  <Default Extension=".txt" ContentType="text/plain"/>
  <Default Extension=".css" ContentType="text/css"/>
  <Default Extension=".html" ContentType="text/html"/>
  <Default Extension=".svg" ContentType="image/svg+xml"/>
  <Default Extension=".png" ContentType="image/png"/>
  <Default Extension=".jpg" ContentType="image/jpeg"/>
  <Default Extension=".gif" ContentType="image/gif"/>
  <Default Extension=".ico" ContentType="image/x-icon"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
  <Default Extension=".node" ContentType="application/octet-stream"/>
  <Default Extension=".exe" ContentType="application/octet-stream"/>
  <Default Extension=".bin" ContentType="application/octet-stream"/>
  <Default Extension=".plist" ContentType="text/xml"/>
  <Default Extension=".py" ContentType="text/plain"/>
  <Default Extension=".yml" ContentType="text/plain"/>
  <Default Extension=".yaml" ContentType="text/plain"/>
  <Default Extension=".map" ContentType="application/json"/>
</Types>
"""


def esc(s):
    return (str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            .replace('"', '&quot;'))


def build(src_dir, out_path):
    pkg = json.load(io.open(os.path.join(src_dir, 'package.json'), encoding='utf-8'))
    name = pkg['name']
    publisher = pkg['publisher']
    version = pkg['version']
    display = pkg.get('displayName') or name
    desc = pkg.get('description') or ''
    engine = (pkg.get('engines') or {}).get('vscode', '*')
    kind = pkg.get('extensionKind') or ['workspace']
    deps = pkg.get('extensionDependencies') or []

    manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="{esc(name)}" Version="{esc(version)}" Publisher="{esc(publisher)}" />
    <DisplayName>{esc(display)}</DisplayName>
    <Description xml:space="preserve">{esc(desc)}</Description>
    <Tags>ai,chat,agent,openai</Tags>
    <Categories>AI</Categories>
    <GalleryFlags>Public</GalleryFlags>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{esc(engine)}" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionDependencies" Value="{esc(','.join(deps))}" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionPack" Value="" />
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="{esc(','.join(kind))}" />
      <Property Id="Microsoft.VisualStudio.Code.LocalizedLanguages" Value="" />
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
"""

    count = 0
    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        z.writestr('[Content_Types].xml', CONTENT_TYPES)
        z.writestr('extension.vsixmanifest', manifest)
        for root, dirs, files in os.walk(src_dir):
            dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, src_dir).replace('\\', '/')
                # 已安装扩展目录里的 .obsolete 之类不要带
                if rel.startswith('.') and rel.endswith('.obsolete'):
                    continue
                z.write(full, 'extension/' + rel)
                count += 1
    size = os.path.getsize(out_path)
    print(f"OK  {out_path}")
    print(f"    {publisher}.{name} v{version}  engine={engine}  files={count}  {size/1024/1024:.1f} MB")


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
