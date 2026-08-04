/// Release channel a build targets. Each channel is a separate Warren
/// deployment, so a build must bind exactly the channel it ships for; the
/// compile-time selector check below makes a typo fail the build.
enum WarrenChannel {
  /// Production deployment, the default when the selector is unset.
  prod('https://api.warrenbrowse.com'),

  /// Beta deployment, reached only by an explicit `WARREN_PRODUCT_ENV=beta`
  /// build.
  beta('https://api.beta.warrenbrowse.com');

  const WarrenChannel(this.apiBase);

  /// Base URL of this channel's account API (the `/v1` control plane).
  final String apiBase;

  /// Maps a `WARREN_PRODUCT_ENV` value; empty or blank means [prod]. Throws on
  /// anything else so a typo cannot ship as prod.
  static WarrenChannel fromSelector(String selector) =>
      switch (selector.trim()) {
        '' || 'prod' => WarrenChannel.prod,
        'beta' => WarrenChannel.beta,
        final String other => throw ArgumentError.value(
            other,
            'WARREN_PRODUCT_ENV',
            'must be prod or beta (or unset for prod)',
          ),
      };
}

/// The raw `WARREN_PRODUCT_ENV` value baked in by
/// `--dart-define=WARREN_PRODUCT_ENV=beta`, empty when unset (meaning prod), so
/// an ordinary build and every test run exercise the prod path.
const String warrenChannelSelector =
    String.fromEnvironment('WARREN_PRODUCT_ENV');

/// The release channel this build targets.
final WarrenChannel warrenChannel =
    WarrenChannel.fromSelector(warrenChannelSelector);

/// Compiled default account API base for [warrenChannel].
final String warrenApiBase = warrenChannel.apiBase;

/// Const-evaluated so an unknown selector fails the build rather than the first
/// call that touches [warrenChannel]. Never referenced: the compile-time assert
/// is the whole point.
// ignore: unused_element
const _CompileTimeSelectorCheck _checkedSelector =
    _CompileTimeSelectorCheck(warrenChannelSelector);

class _CompileTimeSelectorCheck {
  const _CompileTimeSelectorCheck(String selector)
      : assert(
          selector == '' || selector == 'prod' || selector == 'beta',
          'WARREN_PRODUCT_ENV must be prod or beta (or unset for prod)',
        );
}
