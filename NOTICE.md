# Third-party notices

## CodexBar

TokenBar's provider integrations (which endpoints exist, how they are
authenticated and how their responses are read) are based on the research in
[steipete/CodexBar](https://github.com/steipete/CodexBar). TokenBar is an
independent Dart / Flutter implementation, not a port of its source code.

CodexBar is licensed under the MIT License:

```
MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Provider logos

The SVG logos in `assets/provider_icons/` are copied from CodexBar's
`Sources/CodexBar/Resources/` (MIT, see above). Each logo is the trademark of
its owner and is used only to identify that service. See
[assets/provider_icons/README.md](assets/provider_icons/README.md) for the
file mapping.

The MiMo SVG is copied from
[nesszer/Win-CodexBar](https://github.com/nesszer/Win-CodexBar),
`rust/assets/icons/ProviderIcon-mimo.svg` at `v0.70.0`, under the same MIT
License terms above, with Copyright (c) 2025 Peter Steinberger.

## Dependencies

Flutter, Dart and the packages listed in `pubspec.yaml` are used under their
own licenses (mostly BSD-3-Clause, MIT and Apache-2.0). Run `flutter pub deps`
for the full list.

## Windows installer

The installer is built with [Inno Setup](https://jrsoftware.org/isinfo.php). `windows/installer/ChineseSimplified.isl`
is the unofficial Simplified Chinese translation from the Inno Setup repository
(`Files/Languages/Unofficial/ChineseSimplified.isl`, tag `is-6_5_4`, maintained by
Zhenghan Yang), used under the Inno Setup license.
