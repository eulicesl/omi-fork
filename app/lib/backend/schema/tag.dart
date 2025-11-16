class Tag {
  final String id;
  final String uid;
  final String name;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Tag({
    required this.id,
    required this.uid,
    required this.name,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'],
      uid: json['uid'],
      name: json['name'],
      color: json['color'],
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
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
