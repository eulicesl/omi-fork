class Folder {
  final String id;
  final String uid;
  final String name;
  final String? color;
  final String? icon;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  Folder({
    required this.id,
    required this.uid,
    required this.name,
    this.color,
    this.icon,
    required this.position,
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
}
