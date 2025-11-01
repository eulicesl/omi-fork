class Folder {
  String id;
  String uid;
  String name;
  String? color;
  String? icon;
  int position;
  DateTime createdAt;
  DateTime updatedAt;

  Folder({
    required this.id,
    required this.uid,
    required this.name,
    this.color,
    this.icon,
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'],
      uid: json['uid'],
      name: json['name'],
      color: json['color'],
      icon: json['icon'],
      position: json['position'] ?? 0,
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      updatedAt: DateTime.parse(json['updated_at']).toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'color': color,
      'icon': icon,
      'position': position,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  Folder copyWith({
    String? id,
    String? uid,
    String? name,
    String? color,
    String? icon,
    int? position,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Folder(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
