import 'dart:ui';

enum DownloadType {
  video('video'),
  list('list'),
  unknown('unknown');

  const DownloadType(this.apiValue);
  final String apiValue;

  static DownloadType fromApi(String val) {
    return DownloadType.values.firstWhere(
      (e) => e.apiValue == val,
      orElse: () => DownloadType.unknown,
    );
  }
}

enum DownloadState {
  requested('requested', 'Download Requested'),
  pending('pending', 'Download Pending'),
  identifying('identifying', 'Identifying'),
  waitForSelection(
    'wait_for_selection',
    'Waiting for Selection',
  ), // ← el valor que viene del API
  inProgress('in_progress', 'In Progress'),
  completed('completed', 'Download Completed!'),
  failed('failed', 'Download Failed'),
  canceled('canceled', 'Canceled'),
  paused('paused', 'Paused'),
  deleted('deleted', 'Deleted');

  const DownloadState(this.apiValue, this.humanReadable);
  final String apiValue;
  final String humanReadable;

  // Parser estático
  static DownloadState fromApi(String val) {
    return DownloadState.values.firstWhere(
      (e) => e.apiValue == val,
      orElse: () => DownloadState.pending,
    );
  }
}

enum ColorEnum {
  green('green', Color(0xFF4CAF50)), // Verde Material
  yellow('yellow', Color(0xFFFFEB3B)), // Amarillo Material
  red('red', Color(0xFFF44336)), // Rojo Material
  blue('blue', Color(0xFF2196F3)), // Azul Material
  gray('gray', Color(0xFF9E9E9E)); // Gris Material

  const ColorEnum(this.apiValue, this.color);
  final String apiValue;
  final Color color;

  static ColorEnum fromApi(String val) {
    return ColorEnum.values.firstWhere(
      (e) => e.apiValue == val,
      orElse: () => ColorEnum.gray,
    );
  }
}

class Info {
  String? url;
  String? image;
  String? file;
  String? title;
  String? platform;
  DownloadType? type;
  String? autor;
  String? creationDate;
  String? duration;

  Info({
    this.url,
    this.image,
    this.file,
    this.title,
    this.platform,
    this.type,
    this.autor,
    this.creationDate,
    this.duration,
  });

  factory Info.fromJson(Map<String, dynamic> json) => Info(
    url: json['url']?.toString(),
    image: json['image']?.toString(),
    file: json['file']?.toString(),
    title: json['title']?.toString(),
    platform: json['platform']?.toString(),
    type: _parseType(json['type']),
    autor: json['autor']?.toString(),
    creationDate: json['creation_date']?.toString(),
    duration: json['duration']?.toString(),
  );

  static DownloadType? _parseType(String? val) {
    if (val == null) return null;
    return DownloadType.fromApi(val);
  }
}

class State {
  DownloadState? value;
  String? subState;
  ColorEnum? subStateColor;
  String? progressLabel;
  double? progressValue;
  ColorEnum? progressColor;
  String? speed;
  String? timeSpent;
  String? timeTotal;
  String? timeLeft;

  State({
    this.value,
    this.subState,
    this.subStateColor,
    this.progressLabel,
    this.progressValue,
    this.progressColor,
    this.speed,
    this.timeSpent,
    this.timeTotal,
    this.timeLeft,
  });

  factory State.fromJson(Map<String, dynamic> json) => State(
    value: _parseState(json['value']),
    subState: json['sub_state']?.toString(),
    subStateColor: _parseColor(json['sub_state_color']),
    progressLabel: json['progress_label']?.toString(),
    progressValue: json['progress_value'] != null
        ? (json['progress_value'] as num).toDouble()
        : null,
    progressColor: _parseColor(json['progress_color']),
    speed: json['speed']?.toString(),
    timeSpent: json['time_spent']?.toString(),
    timeTotal: json['time_total']?.toString(),
    timeLeft: json['time_left']?.toString(),
  );

  static DownloadState? _parseState(String? val) {
    if (val == null) return null;
    return DownloadState.fromApi(val);
  }

  static ColorEnum? _parseColor(String? val) {
    if (val == null) return null;
    return ColorEnum.fromApi(val);
  }
}

class Delta {
  String? id;
  String? subId;
  State? status;
  Info? info;
  Delta({this.id, this.subId, this.status, this.info});

  factory Delta.fromJson(Map<String, dynamic> json) => Delta(
    id: json['id']?.toString(),
    subId: json['sub_id']?.toString(),
    status: json['status'] != null ? State.fromJson(json['status']) : null,
    info: json['info'] != null ? Info.fromJson(json['info']) : null,
  );
}

class SubDownload {
  String? subId;
  String? parentId;
  Info? info;
  State? state;
  SubDownload({this.subId, this.parentId, this.info, this.state});
  factory SubDownload.fromJson(Map<String, dynamic> json) => SubDownload(
    subId: json['sub_id']?.toString(),
    parentId: json['parent_id']?.toString(),
    info: json['info'] != null ? Info.fromJson(json['info']) : null,
    state: json['state'] != null ? State.fromJson(json['state']) : null,
  );
}

class Download {
  String? id;
  Info? info;
  State? state;
  Map<String, dynamic>? options;
  List<SubDownload>? subDownloads;

  Download({this.id, this.info, this.state, this.options, this.subDownloads});

  factory Download.fromJson(Map<String, dynamic> json) => Download(
    id: json['id']?.toString(),
    info: json['info'] != null ? Info.fromJson(json['info']) : null,
    state: json['state'] != null ? State.fromJson(json['state']) : null,
    options: json['options'] as Map<String, dynamic>?,
    subDownloads: json['sub_descargas'] != null
        ? (json['sub_descargas'] as List)
              .map((e) => SubDownload.fromJson(e))
              .toList()
        : null,
  );
}
