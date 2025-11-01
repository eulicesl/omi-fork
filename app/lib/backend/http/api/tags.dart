import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omi/backend/http/shared.dart';
import 'package:omi/backend/schema/tag.dart';
import 'package:omi/env/env.dart';

Future<bool> createTagServer(String name, {String? color}) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags',
    headers: {},
    method: 'POST',
    body: json.encode({
      'name': name,
      if (color != null) 'color': color,
    }),
  );
  if (response == null) return false;
  debugPrint('createTag response: ${response.body}');
  return response.statusCode == 200;
}

Future<List<Tag>> getTags({int limit = 100, int offset = 0}) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags?limit=$limit&offset=$offset',
    headers: {},
    method: 'GET',
    body: '',
  );
  if (response == null) return [];
  debugPrint('getTags response: ${response.body}');
  List<dynamic> tags = json.decode(response.body);
  return tags.map((tag) => Tag.fromJson(tag)).toList();
}

Future<Tag?> getTagServer(String tagId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags/$tagId',
    headers: {},
    method: 'GET',
    body: '',
  );
  if (response == null) return null;
  debugPrint('getTag response: ${response.body}');
  return Tag.fromJson(json.decode(response.body));
}

Future<bool> updateTagServer(String tagId, {String? name, String? color}) async {
  Map<String, dynamic> updates = {};
  if (name != null) updates['name'] = name;
  if (color != null) updates['color'] = color;

  if (updates.isEmpty) return false;

  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags/$tagId',
    headers: {},
    method: 'PATCH',
    body: json.encode(updates),
  );
  if (response == null) return false;
  debugPrint('updateTag response: ${response.body}');
  return response.statusCode == 200;
}

Future<bool> deleteTagServer(String tagId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags/$tagId',
    headers: {},
    method: 'DELETE',
    body: '',
  );
  if (response == null) return false;
  debugPrint('deleteTag response: ${response.body}');
  return response.statusCode == 200;
}
