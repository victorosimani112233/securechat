import '../l10n/generated/app_localizations.dart';

String disappearingTimerDurationLabel(AppLocalizations l10n, int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  if (duration == Duration.zero) return l10n.off;
  if (duration.inHours < 24) return l10n.hours(duration.inHours);
  return l10n.days(duration.inDays);
}

String localDisappearingTimerNotice(AppLocalizations l10n, int durationMs) =>
    durationMs == 0
    ? l10n.disappearing_timer_disabled_by_you
    : l10n.disappearing_timer_enabled_by_you(
        disappearingTimerDurationLabel(l10n, durationMs),
      );

String remoteDisappearingTimerNotice(
  AppLocalizations l10n, {
  required String sender,
  required int durationMs,
}) => durationMs == 0
    ? l10n.disappearing_timer_disabled_by_peer(sender)
    : l10n.disappearing_timer_enabled_by_peer(
        sender,
        disappearingTimerDurationLabel(l10n, durationMs),
      );
