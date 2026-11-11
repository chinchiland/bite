# The body

`Bite/Resources/Body/body.bin` is the body that "Your body" draws: MakeHuman's base mesh, its
young man's and young woman's shapes, the nine muscle by weight targets of each, and a reduced
skeleton of 20 bones with MakeHuman's own skin weights. MakeHuman's assets are CC0
(makehumancommunity/makehuman, makehuman/data), so the packed file ships with the app.

To pack it again, with MakeHuman's data folder at hand:

```sh
python3 tools/body/pack_body.py <makehuman data folder> Bite/Resources/Body/body.bin
```

`pack_body.py` says what it reads and how the file is laid out. The app reads it in
`Bite/Services/BodyRig.swift` (Foundation only, so `tools/check.sh` loads, poses and skins it in
the logic tests); `Bite/Views/Body` draws it with Metal, from shaders compiled at run time
(`BodyShader.swift`), so the app needs no Metal toolchain to build.
