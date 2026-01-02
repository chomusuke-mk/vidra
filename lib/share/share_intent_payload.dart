class ShareIntentPayload {
  ShareIntentPayload({
    required this.urls,
    required this.rawText,
    required this.timestamp,
    this.displayName,
    this.presetId,
    this.sourcePackage,
    this.subject,
    this.directShare = false,
  });

  final List<String> urls;
  final String rawText;
  final DateTime timestamp;
  final String? displayName;
  final String? presetId;
  final String? sourcePackage;
  final String? subject;
  final bool directShare;

  factory ShareIntentPayload.fromMap(Map<dynamic, dynamic> payload) {
    final rawUrls = payload['urls'];
    final urls = rawUrls is Iterable
        ? rawUrls
              .map((url) => '$url'.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : <String>[];
    final rawText = payload['rawText']?.toString() ?? '';
    final presetId = payload['presetId']?.toString();
    final displayName = payload['displayName']?.toString();
    final sourcePackage = payload['sourcePackage']?.toString();
    final subject = payload['subject']?.toString();
    final directShareValue = payload['directShare'];
    final timestampValue = payload['timestamp'];
    final timestamp = timestampValue is num
        ? DateTime.fromMillisecondsSinceEpoch(
            timestampValue.toInt(),
            isUtc: false,
          )
        : DateTime.now();

    return ShareIntentPayload(
      urls: urls,
      rawText: rawText,
      displayName: displayName?.isEmpty == true ? null : displayName,
      presetId: presetId?.isEmpty == true ? null : presetId,
      sourcePackage: sourcePackage?.isEmpty == true ? null : sourcePackage,
      subject: subject?.isEmpty == true ? null : subject,
      directShare: directShareValue is bool && directShareValue,
      timestamp: timestamp,
    );
  }

  String joinedUrls([String separator = '\n']) {
    if (urls.isEmpty) {
      return rawText.trim();
    }
    return urls.join(separator);
  }

  String get label {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }
    if (urls.isNotEmpty) {
      return urls.first;
    }
    return rawText;
  }
}
