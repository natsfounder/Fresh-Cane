import 'package:flutter/foundation.dart';

/// Immutable domain model representing a menu category in Fresh Cane POS.
///
/// Corresponds to PostgreSQL table `public.categories`.
@immutable
class Category {
  final String id;
  final String name;
  final String slug;
  final int displayOrder;
  final bool isActive;
  final String? imageUrl;

  const Category({
    required this.id,
    required this.name,
    required this.slug,
    required this.displayOrder,
    required this.isActive,
    this.imageUrl,
  });

  /// Factory constructor to deserialize JSON returned from Supabase.
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      imageUrl: json['image_url'] as String?,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'display_order': displayOrder,
      'is_active': isActive,
      'image_url': imageUrl,
    };
  }

  Category copyWith({
    String? id,
    String? name,
    String? slug,
    int? displayOrder,
    bool? isActive,
    String? imageUrl,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category &&
        other.id == id &&
        other.name == name &&
        other.slug == slug &&
        other.displayOrder == displayOrder &&
        other.isActive == isActive &&
        other.imageUrl == imageUrl;
  }

  @override
  int get hashCode => Object.hash(id, name, slug, displayOrder, isActive, imageUrl);

  @override
  String toString() =>
      'Category(id: $id, name: $name, slug: $slug, displayOrder: $displayOrder, isActive: $isActive, imageUrl: $imageUrl)';
}
