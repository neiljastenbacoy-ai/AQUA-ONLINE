import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'art.dart';
import 'constants.dart';
import 'icons.dart';
import 'palette.dart';
import 'state.dart';

/* ================= styling helpers ================= */

TextStyle tx(
  BuildContext c,
  double size, {
  FontWeight w = FontWeight.w400,
  bool disp = false,
  Color? color,
  double? ls,
  double? h,
  List<FontFeature>? fontFeatures,
}) {
  final p = Pal.of(c);
  return TextStyle(
    fontFamily: disp ? 'Poppins' : 'Nunito Sans',
    fontSize: size,
    fontWeight: w,
    color: color ?? p.ink,
    letterSpacing: ls,
    height: h,
    fontFeatures: fontFeatures,
  );
}

TextStyle para(
  BuildContext c, {
  Color? color,
  double size = 15,
  FontWeight w = FontWeight.w400,
}) => tx(c, size, w: w, color: color, h: 1.45);

typedef SelectCb = void Function(String value);

/* ================= interaction primitives ================= */

/// Pressable surface with the affordances a bare [GestureDetector] lacks: hover
/// highlight, keyboard focus ring, Enter/Space activation and a pressed state.
/// Every tappable control in the design system sits on one of these.
class TapSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool opaque;
  final String? semanticLabel;
  final bool? semanticToggled;
  final bool? semanticSelected;
  final bool semanticButton;
  final FocusNode? focusNode;
  const TapSurface({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.opaque = true,
    this.semanticLabel,
    this.semanticToggled,
    this.semanticSelected,
    this.semanticButton = true,
    this.focusNode,
  });

  @override
  State<TapSurface> createState() => _TapSurfaceState();
}

class _TapSurfaceState extends State<TapSurface> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final enabled = widget.onTap != null;
    final alpha = _down ? .18 : (_hover ? .09 : (_focus ? .05 : 0.0));
    Widget body = Stack(
      children: [
        widget.child,
        if (alpha > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  color: (p.isDark ? Colors.white : p.blue).withValues(
                    alpha: alpha,
                  ),
                ),
              ),
            ),
          ),
        if (_focus)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: Border.all(color: p.blueHi, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
    body = FocusableActionDetector(
      enabled: enabled,
      focusNode: widget.focusNode,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (v) {
        if (v != _focus) setState(() => _focus = v);
      },
      onShowHoverHighlight: (v) {
        if (v != _hover) setState(() => _hover = v);
      },
      child: GestureDetector(
        behavior: widget.opaque
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        child: body,
      ),
    );
    if (widget.semanticLabel == null &&
        widget.semanticToggled == null &&
        widget.semanticSelected == null) {
      return body;
    }
    return Semantics(
      container: true,
      button: widget.semanticButton,
      enabled: enabled,
      toggled: widget.semanticToggled,
      selected: widget.semanticSelected,
      label: widget.semanticLabel,
      child: body,
    );
  }
}

/// Single icon action (`.ibtn`): 44px hit target, optional count pip.
class IconAction extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final double iconSize;
  final double box;
  final Color? color;
  final String? label;
  final String? pip;
  final Color? pipBorder;
  const IconAction(
    this.icon, {
    super.key,
    this.onTap,
    this.iconSize = 20,
    this.box = 44,
    this.color,
    this.label,
    this.pip,
    this.pipBorder,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Ic(icon, size: iconSize, color: color ?? p.link),
            if (pip != null)
              Positioned(
                top: 3,
                right: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.pip,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: pipBorder ?? p.card, width: 2),
                  ),
                  child: Text(
                    pip!,
                    style: tx(
                      context,
                      11,
                      w: FontWeight.w800,
                      color: Colors.white,
                      h: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox row (`.checkrow`) — one look for every opt-in toggle in the app.
class CheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  const CheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: () => onChanged(!value),
      semanticLabel: label,
      semanticToggled: value,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? p.blue : p.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: value ? p.blue : p.line, width: 2),
              ),
              alignment: Alignment.center,
              child: value ? Ic('check', size: 15, color: Colors.white) : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: tx(context, 15, w: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

/// Search input matching [AquaField]: leading magnifier + a clear button.
class AquaSearch extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  const AquaSearch({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search',
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: 1.5),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: para(context),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: p.card,
          constraints: const BoxConstraints(minHeight: 50),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Ic('search', size: 20, color: p.muted),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: v.text.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: Ic('close', size: 18, color: p.muted),
                  ),
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          enabledBorder: border(p.line),
          focusedBorder: border(p.blueHi),
        ),
      ),
    );
  }
}

/* ================= phone frame ================= */

const double kFrameWidth = 440;
const double kFrameRadius = 30;

/// Wide windows (desktop / web) keep the mobile layout inside a phone frame
/// instead of stretching it across the whole window.
bool framedLayout(BuildContext c) => MediaQuery.sizeOf(c).width >= 520;

/// The frame itself. Shared by the shell, the drawer overlay, sheets and the
/// full-screen pages that live above the shell (map pickers).
Widget phoneFrame(
  BuildContext c, {
  required Widget child,
  Color? background,
  bool border = true,
  bool shadow = true,
}) {
  final p = Pal.of(c);
  return Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      width: kFrameWidth,
      constraints: const BoxConstraints(maxHeight: 900),
      decoration: BoxDecoration(
        color: background ?? p.bg,
        borderRadius: BorderRadius.circular(kFrameRadius),
        border: border ? Border.all(color: p.line) : null,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x47102A64),
                  offset: Offset(0, 20),
                  blurRadius: 60,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/* ================= buttons ================= */

enum BtnKind { primary, alt, ghost, danger, green, outd }

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String? icon; // Ic name
  final double iconSize;
  final BtnKind kind;
  final bool small;
  final bool busy;
  const Btn(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.iconSize = 22,
    this.kind = BtnKind.primary,
    this.small = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final dis = onPressed == null || busy;
    Color? fgColor;
    BoxDecoration? deco;
    switch (kind) {
      case BtnKind.primary:
        deco = BoxDecoration(
          gradient: Pal.btnBlue,
          borderRadius: BorderRadius.circular(small ? 14 : 16),
          boxShadow: [
            if (!small)
              const BoxShadow(
                color: Color(0x471565D8),
                offset: Offset(0, 6),
                blurRadius: 14,
              ),
          ],
        );
        fgColor = Colors.white;
      case BtnKind.green:
        deco = BoxDecoration(
          gradient: Pal.btnGreen,
          borderRadius: BorderRadius.circular(small ? 14 : 16),
          boxShadow: [
            if (!small)
              const BoxShadow(
                color: Color(0x47127A55),
                offset: Offset(0, 6),
                blurRadius: 14,
              ),
          ],
        );
        fgColor = Colors.white;
      case BtnKind.alt:
        deco = BoxDecoration(
          color: p.ice,
          borderRadius: BorderRadius.circular(small ? 14 : 16),
          border: Border.all(color: p.line, width: 1),
        );
        fgColor = p.link;
      case BtnKind.ghost:
        fgColor = p.link;
      case BtnKind.danger:
        deco = BoxDecoration(
          color: p.danger,
          borderRadius: BorderRadius.circular(small ? 14 : 16),
        );
        fgColor = Colors.white;
      case BtnKind.outd:
        deco = BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(small ? 14 : 16),
          border: Border.all(color: p.danger, width: 1.5),
        );
        fgColor = p.danger;
    }
    // 44px keeps the small variant on the minimum comfortable touch target.
    final h = small ? 44.0 : 52.0;
    final fSize = small ? 14.0 : 16.0;
    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // The spinner replaces the icon so the label never jumps sideways.
        if (busy) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fgColor),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Ic(icon!, size: iconSize, color: fgColor),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tx(
              context,
              fSize,
              w: FontWeight.w700,
              disp: true,
              color: fgColor,
            ),
          ),
        ),
      ],
    );
    return Opacity(
      // Busy keeps full strength so the spinner reads; only a null callback
      // (a field the form still needs) is drawn as disabled.
      opacity: onPressed == null ? 0.5 : 1,
      child: TapSurface(
        onTap: dis ? null : onPressed,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(small ? 14 : 16),
        child: Container(
          width: small ? null : double.infinity,
          height: h,
          alignment: Alignment.center,
          padding: small
              ? const EdgeInsets.symmetric(horizontal: 16)
              : const EdgeInsets.symmetric(horizontal: 8),
          decoration: deco,
          child: row,
        ),
      ),
    );
  }
}

/* ================= segmented control ================= */

class SegItem {
  final String value;
  final String label;
  final String? icon;
  const SegItem(this.value, this.label, {this.icon});
}

class SegBar extends StatelessWidget {
  final List<SegItem> items;
  final String value;
  final SelectCb onSelect;
  final bool small;
  const SegBar({
    super.key,
    required this.items,
    required this.value,
    required this.onSelect,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: p.ice,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          for (final it in items) ...[
            Expanded(
              child: TapSurface(
                onTap: () => onSelect(it.value),
                semanticLabel: it.label,
                semanticSelected: value == it.value,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: small ? 42 : 46,
                  decoration: BoxDecoration(
                    gradient: value == it.value ? Pal.btnBlue : null,
                    color: value == it.value ? null : p.card,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: value == it.value
                        ? const [
                            BoxShadow(
                              color: Color(0x471565D8),
                              offset: Offset(0, 4),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.icon != null) ...[
                        Ic(
                          it.icon!,
                          size: 18,
                          color: value == it.value ? Colors.white : p.link,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(
                            context,
                            small ? 12.5 : 14,
                            disp: true,
                            w: FontWeight.w700,
                            color: value == it.value ? Colors.white : p.link,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (it != items.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/* ================= filter chips ================= */

class FilterChips extends StatelessWidget {
  final List<SegItem> items;
  final String value;
  final SelectCb onSelect;
  const FilterChips({
    super.key,
    required this.items,
    required this.value,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          TapSurface(
            onTap: () => onSelect(it.value),
            semanticLabel: it.label,
            semanticSelected: value == it.value,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: value == it.value ? p.blue : p.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: value == it.value ? p.blue : p.line,
                  width: 1.5,
                ),
              ),
              // Center with widthFactor hugs the text; a plain alignment would
              // make the Container expand to full row width inside Wrap.
              child: Center(
                widthFactor: 1,
                child: Text(
                  it.label,
                  style: tx(
                    context,
                    13.5,
                    disp: true,
                    w: FontWeight.w700,
                    color: value == it.value ? Colors.white : p.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ================= stepper ================= */

class StepperCtl extends StatelessWidget {
  final int qty;
  final ValueChanged<int> onChange;
  final bool small;
  const StepperCtl({
    super.key,
    required this.qty,
    required this.onChange,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final bs = small ? 38.0 : 42.0;
    Widget roundBtn(IconData? ic2, String name, bool plus, bool disabled) {
      return TapSurface(
        onTap: disabled ? null : () => onChange(plus ? 1 : -1),
        semanticLabel: plus ? 'Increase quantity' : 'Decrease quantity',
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: bs,
          height: bs,
          decoration: BoxDecoration(
            color: plus ? p.blue : p.ice,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Opacity(
            opacity: disabled ? 0.4 : 1,
            child: Ic(name, size: 18, color: plus ? Colors.white : p.link),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          roundBtn(null, 'minus', false, qty <= 1),
          Container(
            constraints: BoxConstraints(minWidth: small ? 28 : 34),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            child: Text(
              '$qty',
              style: tx(
                context,
                small ? 16 : 18,
                disp: true,
                w: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          roundBtn(null, 'plus', true, qty >= 20),
        ],
      ),
    );
  }
}

/* ================= cards / rows ================= */

class AquaCard extends StatelessWidget {
  final Widget child;
  final Color? background;
  final Color? borderColor;
  final bool borderLeft;
  final EdgeInsets? padding;
  const AquaCard({
    super.key,
    required this.child,
    this.background,
    this.borderColor,
    this.borderLeft = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background ?? p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? p.line),
        boxShadow: Pal.of(context).shadow,
      ),
      child: child,
    );
  }
}

/* ================= auth scaffolding ================= */

/// Gradient hero shared by the three sign-in screens.
///
/// Capped near 190dp so the card's primary action stays above the fold on a
/// 640dp-tall phone, and the artwork sits *behind* the copy (bleeding off the
/// right edge) instead of taking a column beside it — the old side-by-side
/// row ate 278dp and pushed the Log In button off-screen.
class AuthHero extends StatelessWidget {
  final String title;
  final String sub;
  final Widget? art;
  const AuthHero({super.key, required this.title, required this.sub, this.art});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: Pal.auth),
      child: ClipRect(
        child: Stack(
          children: [
            if (art != null)
              Positioned(
                right: -20,
                bottom: 22,
                child: Opacity(opacity: 0.3, child: art!),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  18, 16 + MediaQuery.of(context).padding.top, 18, 56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AquaLogo(color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tx(context, 24,
                        disp: true, w: FontWeight.w700, color: Colors.white, h: 1.1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: para(context,
                        color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ],
              ),
            ),
            // The wave owns the last 46dp, so the card can tuck under it.
            Positioned(
                left: 0, right: 0, bottom: 0, child: Wave(height: 46, w2: p.bg)),
          ],
        ),
      ),
    );
  }
}

/// Scroll body that tucks its content up under the hero wave.
Widget authOverlapScroll(Widget child, {double overlap = 26, double bottom = 28}) {
  return Expanded(
    child: SingleChildScrollView(
      clipBehavior: Clip.none,
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + overlap),
      child: Transform.translate(
        offset: Offset(0, -overlap),
        // Same height as top padding: the band above the viewport can never be
        // tapped, so it stays empty instead of covering the first control.
        child: Padding(padding: EdgeInsets.only(top: overlap), child: child),
      ),
    ),
  );
}

/// Inline text action (link colour, 36dp tall) used around the sign-in card.
class TxtLink extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onTap;
  const TxtLink(this.label, {super.key, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Ic(icon!, size: 15, color: p.link),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 13.5, w: FontWeight.w700, color: p.link),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Staff sign-in" switcher.
///
/// The role belongs to the account, not to the sign-in decision, so it lives
/// behind one link instead of occupying the top third of the card.
Future<void> showAuthRoleSheet(BuildContext context, AppState s) {
  return showAquaSheet<void>(
    context,
    title: 'Who is signing in?',
    body: VGap([
      _RoleRow(s, 'customer', 'Customer', 'Order and track your water', 'user'),
      _RoleRow(s, 'rider', 'Rider', 'See and run assigned deliveries', 'truck'),
      _RoleRow(s, 'admin', 'Station admin', 'Orders, riders and stock', 'store'),
    ], gap: 10),
  );
}

class _RoleRow extends StatelessWidget {
  final AppState s;
  final String role;
  final String label;
  final String sub;
  final String icon;
  const _RoleRow(this.s, this.role, this.label, this.sub, this.icon);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final on = s.authRole == role;
    return TapSurface(
      onTap: () {
        Navigator.of(context).pop();
        s.authRole = role;
        s.authTab = 'login';
        s.updateUI();
      },
      semanticLabel: 'Sign in as $label',
      semanticSelected: on,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: on ? p.ice : p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? p.blueHi : p.line, width: 1.5),
        ),
        child: Row(children: [
          Ic(icon, size: 22, color: p.link),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: tx(context, 15, disp: true, w: FontWeight.w700)),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: para(context, color: p.muted, size: 13)),
            ]),
          ),
          if (on) Ic('check', size: 18, color: p.blue),
        ]),
      ),
    );
  }
}

/// `.pad .stack` — vertical content column with 14px gaps on 16/28 padding.
class PadScroll extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  const PadScroll({super.key, required this.children, this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Fill the viewport even when the content is short. A scroll view that
        // shrink-wraps gets centred by ancestor Stacks (the screen switcher),
        // which floated empty states and filter rows to the middle of the
        // screen instead of pinning them under the app bar.
        final padV = 16.0 + 28.0;
        final minH = c.maxHeight.isFinite
            ? (c.maxHeight - padV).clamp(0.0, double.infinity)
            : 0.0;
        return SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Generic vertical stack with gap (`.stack` / custom gap via style attr).
class VGap extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const VGap(this.children, {super.key, this.gap = 14, this.crossStart = true});
  final bool crossStart;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossStart
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) SizedBox(height: gap),
        ],
      ],
    );
  }
}

class RowW extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final MainAxisAlignment align;
  final CrossAxisAlignment cross;
  const RowW(
    this.children, {
    super.key,
    this.gap = 10,
    this.align = MainAxisAlignment.start,
    this.cross = CrossAxisAlignment.center,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: cross,
      mainAxisAlignment: align,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) SizedBox(width: gap),
        ],
      ],
    );
  }
}

class SectionHead extends StatelessWidget {
  final String title;
  final String? icon;
  final double iconSize;
  const SectionHead(this.title, {super.key, this.icon, this.iconSize = 24});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidget = Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tx(context, 18, disp: true, w: FontWeight.w700),
        );
        return Row(
          mainAxisSize: constraints.hasBoundedWidth
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Ic(icon!, size: iconSize, color: p.blue),
              const SizedBox(width: 8),
            ],
            if (constraints.hasBoundedWidth)
              Flexible(child: titleWidget)
            else
              titleWidget,
          ],
        );
      },
    );
  }
}

/* ================= dashboard kit ================= */

/// Gradient header shared by the three dashboards.
///
/// The heroes it replaces were 176–188dp of greeting before the first useful
/// pixel (37% of a 640dp phone). This one is ~132dp and only grows when a
/// control rides under the title. It owns its wave so every dashboard tucks
/// its body under the header the same way the sign-in screens do.
class DashHero extends StatelessWidget {
  final String title;
  final String sub;
  final Widget? art;
  final Widget? trailing;
  const DashHero({
    super.key,
    required this.title,
    required this.sub,
    this.art,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 132),
      decoration: const BoxDecoration(gradient: Pal.hero),
      child: Stack(
        children: [
          // Behind the copy at 26%: texture, not a column that eats width.
          if (art != null)
            Positioned(
              right: -8,
              bottom: 22,
              child: Opacity(opacity: 0.26, child: art!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx(context, 24,
                      disp: true, w: FontWeight.w700, color: Colors.white, h: 1.15),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: para(context,
                      color: Colors.white.withValues(alpha: 0.9), size: 13.5),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 12),
                  trailing!,
                ],
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: Wave(height: 40, w2: p.bg)),
        ],
      ),
    );
  }
}

/// One figure in a [StatRow]: icon + value on the first line, label under it.
///
/// Values stay in ink so four tiles read as one set of numbers; the accent
/// colour lives on the icon and the tile background.
class StatTile extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.bg,
    required this.fg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticLabel: '$value $label',
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: p.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Ic(icon, size: 15, color: fg),
                const SizedBox(width: 5),
                Expanded(
                  // A four-digit count or "₱2.4k" shrinks instead of overflowing.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: numStyle(context,
                          size: 21, w: FontWeight.w700, disp: true, color: p.ink),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tx(context, 11.5, w: FontWeight.w700, color: p.muted, h: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

/// Evenly split row of [StatTile]s. Four is the most that stays legible at
/// 320dp with large text.
class StatRow extends StatelessWidget {
  final List<StatTile> tiles;
  const StatRow(this.tiles, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          Expanded(child: tiles[i]),
          if (i != tiles.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// A dashboard task rather than a notification: accent bar, icon, what needs
/// doing and the verb that does it. The whole row is the tap target.
class ActionRow extends StatelessWidget {
  final Color accent;
  final String icon;
  final String title;
  final String? sub;
  final String verb;
  final VoidCallback onTap;
  const ActionRow({
    super.key,
    required this.accent,
    required this.icon,
    required this.title,
    this.sub,
    required this.verb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticLabel: '$title. $verb',
      semanticButton: false,
      borderRadius: BorderRadius.circular(16),
      // Flutter only allows a borderRadius on a uniform-color border, so the
      // rounded corners come from a clip while the left bar stays a border.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: p.shadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: p.card,
              border: Border(
                left: BorderSide(color: accent, width: 5),
                top: BorderSide(color: p.line),
                right: BorderSide(color: p.line),
                bottom: BorderSide(color: p.line),
              ),
            ),
            child: Row(
              children: [
                Ic(icon, size: 20, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tx(context, 14, w: FontWeight.w700, h: 1.25),
                      ),
                      if (sub != null)
                        Text(
                          sub!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: para(context, color: p.muted, size: 12.5),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  verb,
                  style: tx(context, 12.5, w: FontWeight.w800, color: p.link),
                ),
                Ic('chev', size: 16, color: p.link),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title plus its "see all"-style trailing action (the row every
/// dashboard repeats).
class SectionRow extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;
  const SectionRow(this.title, {super.key, this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SectionHead(title)),
        if (action != null)
          Btn(action!, kind: BtnKind.ghost, small: true, onPressed: onTap),
      ],
    );
  }
}

/// Dependency-free bar strip for "last 7 days" trends.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color color;
  const Sparkline(this.values,
      {super.key, this.height = 36, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    var maxV = 0.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    const floor = 5.0;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: Container(
                height: maxV <= 0
                    ? floor
                    : floor + (values[i] / maxV) * (height - floor),
                decoration: BoxDecoration(
                  color: color.withValues(
                      alpha: i == values.length - 1 ? 0.95 : 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ================= badges / tags ================= */

/// Status badge; colors per status index 0-5 + trailing dot.
class OrdBadge extends StatelessWidget {
  final int s; // 0..5
  final String? label;
  const OrdBadge(this.s, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final Color bg = switch (s) {
      0 => p.s0bg,
      1 => p.s1bg,
      2 => p.s2bg,
      3 => p.s3bg,
      4 => p.s4bg,
      _ => p.s5bg,
    };
    final Color fg = switch (s) {
      0 => p.s0fg,
      1 => p.s1fg,
      2 => p.s2fg,
      3 => p.s3fg,
      4 => p.s4fg,
      _ => p.s5fg,
    };
    return LayoutBuilder(
      builder: (context, c) {
        final labelWidget = Text(
          label ?? BADGE[s],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tx(context, 12, w: FontWeight.w800, color: fg, ls: 0.2),
        );
        return Container(
          constraints: const BoxConstraints(minHeight: 26),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              // Narrow slots (card headers beside buttons/images) must truncate
              // the label rather than paint overflow stripes.
              if (c.hasBoundedWidth) Flexible(child: labelWidget) else labelWidget,
            ],
          ),
        );
      },
    );
  }
}

class Tag extends StatelessWidget {
  final String label;
  final bool buy;
  final double? fontSize;
  final double? minHeight;
  final EdgeInsets? padding;
  const Tag(
    this.label, {
    super.key,
    this.buy = false,
    this.fontSize,
    this.minHeight,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      height: minHeight ?? 22,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: buy ? p.mintBg : p.ice2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: tx(
          context,
          fontSize ?? 11.5,
          w: FontWeight.w800,
          color: buy ? p.mintFg : p.link,
        ),
      ),
    );
  }
}

/* ================= form controls ================= */

/// Selector row (`.radio`) — dot on the left, any line content on the right.
class RadioRow extends StatelessWidget {
  final bool checked;
  final VoidCallback onTap;
  final Widget content;
  final bool alignTop;
  const RadioRow({
    super.key,
    required this.checked,
    required this.onTap,
    required this.content,
    this.alignTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticToggled: checked,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: checked ? p.ice : p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: checked ? p.blue : p.line, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: alignTop
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Container(
              margin: EdgeInsets.only(top: alignTop ? 6 : 0),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: checked ? p.blue : p.line, width: 2),
              ),
              alignment: Alignment.center,
              child: checked
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.blue,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// Row button (`.rowbtn`) with icon + title/value + chevron.
class RowBtn extends StatelessWidget {
  final String icon;
  final String title;
  final String value;
  final bool warn;
  final VoidCallback? onTap;
  const RowBtn({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.warn = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticLabel: '$title, $value',
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Ic(icon, size: 22, color: p.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: tx(context, 15, w: FontWeight.w700)),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx(
                            context,
                            13.5,
                            w: warn ? FontWeight.w700 : FontWeight.w400,
                            color: warn ? p.peachFg : p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Ic('chev', size: 20, color: p.muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.kv` key/value rows with divider between.
class KvList extends StatelessWidget {
  final List<Widget> rows;
  const KvList({super.key, required this.rows});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: 1, color: Pal.of(context).line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: rows[i],
          ),
        ],
      ],
    );
  }
}

class Avatar extends StatelessWidget {
  final String text;
  final bool sm;
  final Color? bg;
  final Color? fg;
  const Avatar(this.text, {super.key, this.sm = false, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final size = sm ? 48.0 : 64.0;
    final font = sm ? 18.0 : 24.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: bg == null && fg == null ? Pal.avatar : null,
        color: bg,
        border: bg == null && fg == null
            ? Border.all(color: p.ice2, width: 3)
            : null,
      ),
      child: Text(
        text,
        style: tx(
          context,
          font,
          disp: true,
          w: FontWeight.w700,
          color: fg ?? (bg == null ? Colors.white : p.navy),
        ),
      ),
    );
  }
}

/// iOS-style switch styled like the CSS `.switch`.
class AquaSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  const AquaSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: () => onChanged(!value),
      semanticLabel: label,
      semanticToggled: value,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 54,
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? p.blue : p.line,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AquaField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? kbType;
  final TextInputAction? kbAction;
  final bool obscure;
  final bool eyeToggle;
  final String? hint;
  final VoidCallback? onEye;
  final int maxLines;
  final double? minHeight;
  final String? Function(String)? validator;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final String? error;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  /// Shows a value the user owns but must not retype in place — an account
  /// email, for instance. The field keeps its label and styling but takes no
  /// input, so there is no half-valid edit to save.
  final bool readOnly;
  const AquaField(
    this.label,
    this.controller, {
    super.key,
    this.kbType,
    this.kbAction,
    this.obscure = false,
    this.eyeToggle = false,
    this.hint,
    this.onEye,
    this.maxLines = 1,
    this.minHeight,
    this.validator,
    this.onChanged,
    this.focusNode,
    this.error,
    this.autofillHints,
    this.onSubmitted,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget field;
    if (obscure && eyeToggle) {
      field = Stack(
        alignment: Alignment.centerRight,
        children: [
          _inp(context, p, suffixPad: true),
          Positioned(
            right: 2,
            top: 3,
            bottom: 3,
            child: IconButton(
              onPressed: onEye,
              icon: Ic(obscure ? 'eye' : 'eyeoff', size: 20, color: p.muted),
            ),
          ),
        ],
      );
    } else {
      field = _inp(context, p, suffixPad: false);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '$label text field',
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tx(context, 13,
                w: FontWeight.w700,
                color: error != null ? p.danger : p.muted,
                ls: 0.2),
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget _inp(BuildContext context, Pal p, {required bool suffixPad}) {
    return Semantics(
      textField: true,
      enabled: controller.text.isNotEmpty || hint != null,
      child: TextField(
        controller: controller,
        keyboardType: kbType,
        textInputAction: kbAction ?? TextInputAction.next,
        obscureText: obscure,
        readOnly: readOnly,
        maxLines: maxLines,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofillHints: autofillHints,
        focusNode: focusNode,
        style: para(context),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: readOnly ? p.ice : p.card,
          // Field-level messages live under the box (and turn its border red)
          // instead of pushing a single form-wide error line around.
          errorText: error,
          errorMaxLines: 2,
          errorStyle: tx(context, 12.5, w: FontWeight.w700, color: p.danger),
          contentPadding: maxLines > 1
              ? const EdgeInsets.all(14)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          constraints: BoxConstraints(minHeight: minHeight ?? 50),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.line, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.blueHi, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.danger, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.danger, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Error text line (`.err`) — bold red, disappears when empty.
class ErrLine extends StatelessWidget {
  final String text;
  const ErrLine(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox(height: 0);
    return Text(
      text,
      style: tx(context, 13, w: FontWeight.w700, color: Pal.of(context).danger),
    );
  }
}

/* ================= chips ============ */

class Chips extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onSelect;
  final bool wide;
  const Chips({
    super.key,
    required this.options,
    required this.value,
    required this.onSelect,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          TapSurface(
            onTap: () => onSelect(o),
            semanticLabel: o,
            semanticSelected: value == o,
            borderRadius: BorderRadius.circular(wide ? 14 : 999),
            child: Container(
              height: wide ? 46 : 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: value == o ? p.blue : p.card,
                borderRadius: BorderRadius.circular(wide ? 14 : 999),
                border: Border.all(
                  color: value == o ? p.blue : p.line,
                  width: 1.5,
                ),
              ),
              // wide fills the row; otherwise Center with widthFactor hugs the
              // label (plain alignment would stretch every chip full width).
              child: Center(
                widthFactor: wide ? null : 1,
                child: Text(
                  o,
                  style: tx(
                    context,
                    14,
                    w: FontWeight.w700,
                    color: value == o ? Colors.white : p.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/* ================= misc ================= */

/// Truck/other icon inside the `.ni` / `.pinic` 40x40 rounded box.
class IconTile extends StatelessWidget {
  final String icon;
  final double size;
  final Color? bg;
  final Color? fg;
  final double iconSize;
  const IconTile(
    this.icon, {
    super.key,
    this.size = 40,
    this.bg,
    this.fg,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? p.ice2,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Ic(icon, size: iconSize, color: fg ?? p.link),
    );
  }
}

/// `.dock-total` bar used on Order/Checkout docks.
class DockTotal extends StatelessWidget {
  final String main; // "Total"
  final String small; // "(2 Gallons)"
  final String amount;
  const DockTotal({
    super.key,
    required this.main,
    required this.small,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: p.ice,
        borderRadius: BorderRadius.circular(14),
      ),
      // Both halves give way: the label ellipsises and the amount scales down,
      // so a long count or a 1.3x text scale can never overflow the dock.
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: main,
                    style: tx(context, 15, w: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' ',
                    style: tx(context, 15, w: FontWeight.w700),
                  ),
                  TextSpan(
                    text: small,
                    style: tx(context, 13, w: FontWeight.w600, color: p.muted),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amount,
                style: tx(
                  context,
                  19,
                  disp: true,
                  w: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String title;
  final String msg;
  final String? galType;
  final double galH;
  final Widget? action;
  final EdgeInsets padding;
  const EmptyView(
    this.title, {
    super.key,
    required this.msg,
    this.galType,
    this.galH = 104,
    this.action,
    this.padding = const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: padding,
      child: Column(
        children: [
          if (galType != null) Gal(galType!, h: galH),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: tx(context, 20, disp: true, w: FontWeight.w700),
          ),
          // "not found" states pass no message; skip the gap entirely instead of
          // leaving an empty paragraph behind the title.
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: para(context, color: p.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/* ================= bottom sheets ================= */

Future<T?> showAquaSheet<T>(
  BuildContext context, {
  required String title,
  required Widget body,
}) {
  final p = Pal.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final framed = framedLayout(ctx);
      // Keep sheets inside the phone frame on wide windows: same width, same
      // bottom corners, 14px of stage showing underneath.
      final maxH = MediaQuery.of(ctx).size.height * 0.88;
      final sheet = Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: framed
              ? const BorderRadius.vertical(
                  top: Radius.circular(24),
                  bottom: Radius.circular(kFrameRadius),
                )
              : const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: tx(ctx, 20, disp: true, w: FontWeight.w700),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: body,
              ),
            ),
          ],
        ),
      );
      // Lift the sheet above the on-screen keyboard so form fields stay in a
      // fixed, visible position while typing.
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: framed
            ? Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SizedBox(
                  width: kFrameWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: sheet,
                  ),
                ),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: sheet,
              ),
      );
    },
  );
}

/* ================= sidebar drawer content ================= */

class SidePanel extends StatelessWidget {
  final AppState s;
  final void Function(String) onSelect;
  final VoidCallback onClose;
  const SidePanel({
    super.key,
    required this.s,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final items = s.role == 'admin'
        ? const [
            ['adash', 'home', 'Dashboard'],
            ['aorders', 'cart', 'Orders'],
            ['adeliv', 'truck', 'Deliveries'],
            ['aprod', 'box', 'Products & Inventory'],
            ['ausers', 'users', 'Users'],
            ['areports', 'chart', 'Reports'],
            ['profile', 'user', 'My Profile'],
            ['settings', 'gear', 'Settings'],
          ]
        : s.role == 'rider'
        ? const [
            ['rdash', 'home', 'Dashboard'],
            ['rlist', 'box', 'My Deliveries'],
            ['rhistory', 'clock', 'Delivery History'],
            ['rearn', 'coins', 'Earnings'],
            ['profile', 'user', 'My Profile'],
            ['settings', 'gear', 'Settings'],
          ]
        : const [
            ['home', 'home', 'Home'],
            ['order', 'cart', 'Order Water'],
            ['orders', 'box', 'My Orders'],
            ['track', 'pin', 'Track Delivery'],
            ['profile', 'user', 'My Profile'],
            ['settings', 'gear', 'Settings'],
          ];
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: const BoxDecoration(
        gradient: Pal.side,
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: onClose,
              icon: Ic('close', size: 26, color: Colors.white),
            ),
          ),
          AquaLogo(lg: true, color: Colors.white),
          const SizedBox(height: 20),
          Row(
            children: [
              Avatar(
                initialsOf(s.whoAmI()?.name),
                sm: true,
                bg: Colors.white,
                fg: p.navy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.whoAmI()?.name ?? '',
                      style: tx(
                        context,
                        16,
                        disp: true,
                        w: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      s.roleLabel(),
                      style: tx(
                        context,
                        13.5,
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -20,
                  child: Opacity(opacity: 0.55, child: const SideWave()),
                ),
                SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final it in items) ...[
                        _NavItem(
                          active: s.screen == it[0],
                          label: it[2],
                          icon: it[1],
                          onTap: () => onSelect(it[0]),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                        height: 1,
                        color: Colors.white.withValues(alpha: .22),
                      ),
                      _NavItem(
                        active: false,
                        label: 'Logout',
                        icon: 'logout',
                        onTap: () => onSelect('logout-ask'),
                      ),
                      const SizedBox(height: 130),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool active;
  final String label;
  final String icon;
  final VoidCallback onTap;
  const _NavItem({
    required this.active,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return TapSurface(
      onTap: onTap,
      semanticLabel: label,
      semanticSelected: active,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? p.blueHi : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Ic(icon, size: 24, color: Colors.white),
            const SizedBox(width: 16),
            Text(
              label,
              style: tx(
                context,
                15.5,
                disp: true,
                w: active ? FontWeight.w600 : FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ================= screen contract ================= */

/// What a screen builder returns: scrollable content + optional dock + bare flag.
class ScreenView {
  final Widget content;
  final Widget? dock;
  final bool bare; // true = hide the app bar (splash/auth)
  const ScreenView({required this.content, this.dock, this.bare = false});
}

/* ================= misc shared fonts ================= */

/// `.num` — tabular numerals everywhere numbers align.
const numFeatures = [FontFeature.tabularFigures()];

TextStyle numStyle(
  BuildContext c, {
  double size = 15,
  FontWeight w = FontWeight.w400,
  Color? color,
  bool disp = false,
}) => tx(c, size, w: w, color: color, disp: disp, fontFeatures: numFeatures);
