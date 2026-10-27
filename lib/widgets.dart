import 'package:flutter/material.dart';

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

/* ================= buttons ================= */

enum BtnKind { primary, alt, ghost, danger, green, outd }

class Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String? icon; // Ic name
  final double iconSize;
  final BtnKind kind;
  final bool small;
  const Btn(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.iconSize = 22,
    this.kind = BtnKind.primary,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final dis = onPressed == null;
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
    final h = small ? 42.0 : 52.0;
    final fSize = small ? 14.0 : 16.0;
    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
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
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: dis ? null : onPressed,
        child: Opacity(
          opacity: dis ? 0.5 : 1,
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
      ),
    );
  }
}

/// Container-based Btn wrapper with border for alt/outd variants.
class BtnBox extends StatelessWidget {
  final Widget child;
  const BtnBox({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
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
              child: GestureDetector(
                onTap: () => onSelect(it.value),
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
          GestureDetector(
            onTap: () => onSelect(it.value),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
              decoration: BoxDecoration(
                color: value == it.value ? p.blue : p.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: value == it.value ? p.blue : p.line,
                  width: 1.5,
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
    final bs = small ? 34.0 : 40.0;
    Widget roundBtn(IconData? ic2, String name, bool plus, bool disabled) {
      return GestureDetector(
        onTap: disabled ? null : () => onChange(plus ? 1 : -1),
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

/// `.pad .stack` — vertical content column with 14px gaps on 16/28 padding.
class PadScroll extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  const PadScroll({super.key, required this.children, this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
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
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
          Text(
            label ?? BADGE[s],
            style: tx(context, 12, w: FontWeight.w800, color: fg, ls: 0.2),
          ),
        ],
      ),
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
    return GestureDetector(
      onTap: onTap,
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
    return GestureDetector(
      onTap: onTap,
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
  const AquaSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
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
  final bool obscure;
  final bool eyeToggle;
  final String? hint;
  final VoidCallback? onEye;
  final int maxLines;
  final double? minHeight;
  final String? Function(String)? validator;
  const AquaField(
    this.label,
    this.controller, {
    super.key,
    this.kbType,
    this.obscure = false,
    this.eyeToggle = false,
    this.hint,
    this.onEye,
    this.maxLines = 1,
    this.minHeight,
    this.validator,
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
        Text(
          label,
          style: tx(context, 13, w: FontWeight.w700, color: p.muted, ls: 0.2),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget _inp(BuildContext context, Pal p, {required bool suffixPad}) {
    return TextField(
      controller: controller,
      keyboardType: kbType,
      obscureText: obscure,
      maxLines: maxLines,
      style: para(context),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: p.card,
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
          GestureDetector(
            onTap: () => onSelect(o),
            child: Container(
              height: wide ? 46 : 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
              decoration: BoxDecoration(
                color: value == o ? p.blue : p.card,
                borderRadius: BorderRadius.circular(wide ? 14 : 999),
                border: Border.all(
                  color: value == o ? p.blue : p.line,
                  width: 1.5,
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
      child: Row(
        children: [
          Text.rich(
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
          ),
          const Spacer(),
          Text(
            amount,
            style: tx(
              context,
              19,
              disp: true,
              w: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
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
          const SizedBox(height: 10),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: para(context, color: p.muted),
          ),
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
      // Lift the sheet above the on-screen keyboard so form fields stay in a
      // fixed, visible position while typing.
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
        ),
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
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Water Ordering & Delivery System',
              maxLines: 2,
              style: para(
                context,
                color: Colors.white.withValues(alpha: 0.85),
                size: 13.5,
              ),
            ),
          ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? Pal.light.blueHi : Colors.transparent,
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
