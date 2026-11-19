import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dispatch_scale.dart';

class DispatchResponsePanel extends StatelessWidget {
  const DispatchResponsePanel({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
    required this.onAccept,
    required this.onDecline,
    this.elevated = false,
  });

  final int secondsLeft;
  final int totalSeconds;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onDecline;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final colors = _PanelColors.of(context);
    final actionsEnabled = onAccept != null;
    final declineEnabled = onDecline != null;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CountdownCard(
          secondsLeft: secondsLeft,
          totalSeconds: totalSeconds,
          colors: colors,
        ),
        SizedBox(height: scale.countdownToButtonsGap),
        Row(
          children: [
            Expanded(
              flex: 35,
              child: _DeclineButton(
                onPressed: declineEnabled
                    ? () {
                        final action = onDecline;
                        if (action != null) {
                          action();
                        }
                      }
                    : null,
                colors: colors,
              ),
            ),
            SizedBox(width: scale.s(12)),
            Expanded(
              flex: 65,
              child: _AcceptButton(
                onPressed: actionsEnabled
                    ? () {
                        final action = onAccept;
                        if (action != null) {
                          action();
                        }
                      }
                    : null,
                colors: colors,
              ),
            ),
          ],
        ),
      ],
    );

    if (!elevated) return body;

    return Container(
      padding: EdgeInsets.all(scale.s(10)),
      decoration: BoxDecoration(
        color: colors.isDark
            ? const Color(0xF0122D43)
            : const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(scale.s(20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24304770),
            blurRadius: 20,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: body,
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.secondsLeft,
    required this.totalSeconds,
    required this.colors,
  });

  final int secondsLeft;
  final int totalSeconds;
  final _PanelColors colors;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final tone = _CountdownTone.resolve(secondsLeft, colors);
    final progress = totalSeconds > 0
        ? (secondsLeft / totalSeconds).clamp(0.0, 1.0)
        : 0.0;
    final animate = !MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 250)
        : Duration.zero;

    return AnimatedContainer(
      duration: animate,
      curve: Curves.easeInOut,
      constraints: BoxConstraints(minHeight: scale.s(72)),
      padding: EdgeInsets.fromLTRB(
        scale.s(14),
        scale.s(12),
        scale.s(14),
        scale.s(12),
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(scale.cardRadius),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: animate,
                child: Icon(
                  Icons.schedule_outlined,
                  key: ValueKey(tone.accent.toARGB32()),
                  color: tone.accent,
                  size: scale.s(22),
                ),
              ),
              SizedBox(width: scale.s(10)),
              Expanded(
                child: Text(
                  'Time remaining to respond',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tone.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: scale.sp(14),
                    letterSpacing: 0,
                  ),
                ),
              ),
              SizedBox(width: scale.s(8)),
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: tone.accent),
                duration: animate,
                builder: (context, color, _) => Text(
                  '00:${secondsLeft.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color ?? tone.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: scale.sp(24),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: scale.s(10)),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 1, end: progress),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 1000),
            curve: Curves.linear,
            builder: (context, value, child) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: tone.accent),
              duration: animate,
              builder: (context, color, _) => ClipRRect(
                borderRadius: BorderRadius.circular(scale.s(20)),
                child: LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(scale.s(20)),
                  minHeight: scale.s(6),
                  value: value,
                  backgroundColor: tone.track,
                  valueColor: AlwaysStoppedAnimation(color ?? tone.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.onPressed, required this.colors});

  final VoidCallback? onPressed;
  final _PanelColors colors;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(scale.buttonHeight),
        foregroundColor: colors.declineText,
        backgroundColor: colors.declineBackground,
        disabledForegroundColor: colors.declineText.withValues(alpha: 0.4),
        disabledBackgroundColor: colors.declineBackground,
        side: BorderSide(color: colors.declineBorder),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: scale.s(10)),
        textStyle: TextStyle(
          fontSize: scale.sp(15),
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(scale.cardRadius),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/images/dispatch_decline.svg',
            width: scale.s(18),
            height: scale.s(18),
            colorFilter: ColorFilter.mode(
              onPressed == null
                  ? colors.declineText.withValues(alpha: 0.4)
                  : colors.declineText,
              BlendMode.srcIn,
            ),
          ),
          SizedBox(width: scale.s(8)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Decline',
                softWrap: false,
                style: TextStyle(
                  fontSize: scale.sp(15),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.onPressed, required this.colors});

  final VoidCallback? onPressed;
  final _PanelColors colors;

  @override
  Widget build(BuildContext context) {
    final scale = DispatchScale.of(context);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: colors.buttonGradient,
          borderRadius: BorderRadius.circular(scale.cardRadius),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF2866DF).withValues(alpha: 0.22),
                    blurRadius: scale.s(10),
                    offset: Offset(0, scale.s(4)),
                  ),
                ]
              : const [],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(scale.buttonHeight),
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: scale.s(12)),
            textStyle: TextStyle(
              fontSize: scale.sp(15),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(scale.cardRadius),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/images/dispatch_check.svg',
                width: scale.s(18),
                height: scale.s(18),
              ),
              SizedBox(width: scale.s(8)),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Accept response',
                    softWrap: false,
                    style: TextStyle(
                      fontSize: scale.sp(15),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownTone {
  const _CountdownTone({
    required this.accent,
    required this.background,
    required this.track,
    required this.border,
  });

  final Color accent;
  final Color background;
  final Color track;
  final Color border;

  static _CountdownTone resolve(int secondsLeft, _PanelColors colors) {
    if (secondsLeft <= 5) {
      return _CountdownTone(
        accent: colors.urgencyRed,
        background: colors.urgencyRedSoft,
        track: colors.urgencyRedTrack,
        border: colors.urgencyRed.withValues(alpha: 0.35),
      );
    }
    if (secondsLeft <= 10) {
      return _CountdownTone(
        accent: colors.urgencyAmber,
        background: colors.urgencyAmberSoft,
        track: colors.urgencyAmberTrack,
        border: colors.urgencyAmber.withValues(alpha: 0.35),
      );
    }
    return _CountdownTone(
      accent: colors.blueStrong,
      background: colors.urgencyBlueSoft,
      track: colors.blueTrack,
      border: colors.blue.withValues(alpha: 0.28),
    );
  }
}

@immutable
class _PanelColors {
  const _PanelColors({required this.isDark});

  factory _PanelColors.of(BuildContext context) =>
      _PanelColors(isDark: Theme.of(context).brightness == Brightness.dark);

  final bool isDark;

  Color get blue => isDark ? const Color(0xFF70AEFF) : const Color(0xFF2866DF);
  Color get blueStrong =>
      isDark ? const Color(0xFF93C5FD) : const Color(0xFF2856D9);
  Color get blueTrack =>
      isDark ? const Color(0xFF2A4058) : const Color(0xFFD5E4F8);
  Color get urgencyBlueSoft =>
      isDark ? const Color(0xFF152A42) : const Color(0xFFEEF4FC);
  Color get urgencyAmber =>
      isDark ? const Color(0xFFFBBF55) : const Color(0xFFC17A12);
  Color get urgencyAmberSoft =>
      isDark ? const Color(0xFF302617) : const Color(0xFFFFF7E7);
  Color get urgencyAmberTrack =>
      isDark ? const Color(0xFF4A3A22) : const Color(0xFFF3E2C2);
  Color get urgencyRed =>
      isDark ? const Color(0xFFFF737D) : const Color(0xFFDC3545);
  Color get urgencyRedSoft =>
      isDark ? const Color(0xFF351F29) : const Color(0xFFFFF0F0);
  Color get urgencyRedTrack =>
      isDark ? const Color(0xFF4A2A33) : const Color(0xFFF5D0D3);
  Color get declineText =>
      isDark ? const Color(0xFFF1F5FC) : const Color(0xFF102541);
  Color get declineBackground =>
      isDark ? const Color(0xFF162636) : const Color(0xFFF7F9FD);
  Color get declineBorder =>
      isDark ? const Color(0xFF2D415A) : const Color(0xFFD0DBEA);
  LinearGradient get buttonGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF367FF5), Color(0xFF2356D5)],
  );
}
