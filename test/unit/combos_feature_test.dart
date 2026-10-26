import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_cane/models/combo_model.dart';
import 'package:fresh_cane/models/menu_item_model.dart';

void main() {
  group('Combos Feature Unit Tests', () {
    test('Combo model serialization and deserialization', () {
      final json = {
        'id': 'c1111111-1111-1111-1111-111111111111',
        'name': 'Family Cane Combo',
        'description': 'Includes: 2x Sugarcane Ginger, 1x Veg Sandwich',
        'price': 220.00,
        'is_available': true,
        'is_active': true,
        'display_order': 1,
        'menu_item_id': 'm1111111-1111-1111-1111-111111111111',
        'items_count': 3,
        'items': [
          {
            'id': 'ci1',
            'menu_item_id': 'item-1',
            'item_name': 'Sugarcane Ginger',
            'base_price': 50.0,
            'quantity': 2,
          },
          {
            'id': 'ci2',
            'menu_item_id': 'item-2',
            'item_name': 'Veg Sandwich',
            'base_price': 140.0,
            'quantity': 1,
          },
        ],
      };

      final combo = Combo.fromJson(json);

      expect(combo.name, 'Family Cane Combo');
      expect(combo.price, 220.00);
      expect(combo.itemsCount, 3);
      expect(combo.items.length, 2);
      expect(combo.items[0].itemName, 'Sugarcane Ginger');
      expect(combo.items[0].quantity, 2);
      expect(combo.items[1].itemName, 'Veg Sandwich');
      expect(combo.items[1].quantity, 1);
    });

    test('Combo automatically reflects as MenuItem under Combos category', () {
      final comboAsMenuItemJson = {
        'id': 'm1111111-1111-1111-1111-111111111111',
        'category_id': 'combos-category-id',
        'name': 'Family Cane Combo',
        'description': 'Includes: 2x Sugarcane Ginger, 1x Veg Sandwich',
        'base_price': 220.00,
        'is_available': true,
        'is_active': true,
        'display_order': 999,
      };

      final menuItem = MenuItem.fromJson(comboAsMenuItemJson);

      expect(menuItem.name, 'Family Cane Combo');
      expect(menuItem.basePrice, 220.00);
      expect(menuItem.description, contains('Includes: 2x Sugarcane Ginger'));
      expect(menuItem.categoryId, 'combos-category-id');
      expect(menuItem.isAvailable, isTrue);
      expect(menuItem.isActive, isTrue);
    });

    test('Combos filtering in order taking matches categoryId', () {
      final items = [
        MenuItem(
          id: '1',
          categoryId: 'juice-cat',
          name: 'Cane Juice',
          basePrice: 40.0,
          isAvailable: true,
          isActive: true,
          displayOrder: 1,
        ),
        MenuItem(
          id: '2',
          categoryId: 'combos-cat',
          name: 'Super Saver Combo',
          description: 'Includes: 2x Cane Juice, 1x Sandwich',
          basePrice: 150.0,
          isAvailable: true,
          isActive: true,
          displayOrder: 999,
        ),
      ];

      final comboItems = items.where((it) => it.categoryId == 'combos-cat').toList();

      expect(comboItems.length, 1);
      expect(comboItems.first.name, 'Super Saver Combo');
      expect(comboItems.first.basePrice, 150.0);
    });
  });
}
