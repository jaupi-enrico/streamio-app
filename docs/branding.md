# Branding

The launcher icon is the website's own mark, copied from `../../web/public/icons/site-icon.png` to
`assets/icon/site-icon.png`, with two derived variants:

* `app-icon.png` — the mark at 72% on **white**, flattened to RGB. The source art is black on a
  transparent background, so it needs a backdrop to work as an icon at all; white is how the
  favicon reads on a browser tab. iOS additionally rejects icons with an alpha channel.
* `app-icon-foreground.png` — the mark at 74% on transparent, for Android's adaptive icon.
  `flutter_launcher_icons` wraps the foreground in a 16% inset, so 74% lands at ~50% of the final
  icon — about 76% of the launcher's safe-zone circle, which survives a circular mask.

After changing the art:

```bash
dart run flutter_launcher_icons
```

In-app, `lib/shared/widgets/app_logo.dart` draws the same mark through a `srcIn` tint — the source
art is black and would be invisible on the dark theme, which only works because the mark is
monochrome and would flatten a multi-color logo.
