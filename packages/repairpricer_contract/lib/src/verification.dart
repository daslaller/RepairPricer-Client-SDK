/// Subscriber-facing verification badges.
///
/// Split out of the platform's service-fee calculator so the client
/// contract can carry the badge vocabulary without the fee math: the
/// projection rows a subscriber reads include `verification_status` and
/// `verification_level`, so an SDK consumer needs these enums to render a
/// row. How a fee or a verification decision is *produced* stays
/// server-side.
library;


/// Subscriber-facing verification badge.
///
/// `reverification_required` is an internal queue state — UIs should surface
/// it as [VerificationStatus.generic] until the AI re-verifies.
enum VerificationStatus {
  generic,
  verified,
  notVerifiable,
  reverificationRequired;

  static VerificationStatus fromKey(String? key) {
    switch (key) {
      case 'verified':
        return VerificationStatus.verified;
      case 'not_verifiable':
        return VerificationStatus.notVerifiable;
      case 'reverification_required':
        return VerificationStatus.reverificationRequired;
      case 'generic':
      case null:
      case '':
        return VerificationStatus.generic;
      default:
        return VerificationStatus.generic;
    }
  }

  String get key => switch (this) {
        VerificationStatus.generic => 'generic',
        VerificationStatus.verified => 'verified',
        VerificationStatus.notVerifiable => 'not_verifiable',
        VerificationStatus.reverificationRequired => 'reverification_required',
      };

  /// Badge label for RepairX / Heid: Verified | Generic | Not-Verifiable.
  String get badgeLabel => switch (this) {
        VerificationStatus.verified => 'Verified',
        VerificationStatus.notVerifiable => 'Not-Verifiable',
        VerificationStatus.generic || VerificationStatus.reverificationRequired => 'Generic',
      };
}

enum VerificationLevel {
  none,
  minor,
  thorough;

  static VerificationLevel? fromKey(String? key) {
    switch (key) {
      case 'none':
        return VerificationLevel.none;
      case 'minor':
        return VerificationLevel.minor;
      case 'thorough':
        return VerificationLevel.thorough;
      default:
        return null;
    }
  }

  String get key => name;
}
