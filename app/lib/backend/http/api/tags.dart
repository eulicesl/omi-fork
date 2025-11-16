import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omi/backend/http/shared.dart';
import 'package:omi/backend/schema/tag.dart';
import 'package:omi/env/env.dart';

Future<List<Tag>> getTags({
  int limit = 100,
  int offset = 0,
}) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags?limit=$limit&offset=$offset',
    headers: {},
    method: 'GET',
    body: '',
  );

  if (response == null || response.statusCode != 200) return [];

  try {
    var body = utf8.decode(response.bodyBytes);
    var decoded = json.decode(body);
    if (decoded is List) {
      return decoded.map((tag) => Tag.fromJson(tag)).toList();
    }
    return [];
  } catch (e) {
    debugPrint('Error parsing tags: $e');
    return [];
  }
}

Future<Tag?> getTag(String tagId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags/$tagId',
    headers: {},
    method: 'GET',
    body: '',
  );

  if (response == null || response.statusCode != 200) return null;

  try {
    var body = utf8.decode(response.bodyBytes);
    return Tag.fromJson(jsonDecode(body));
  } catch (e) {
    debugPrint('Error parsing tag: $e');
    return null;
  }
}

Future<Tag?> createTag({
  required String name,
  String? color,
}) async {
  var requestBody = {
    'name': name,
  };

  if (color != null) requestBody['color'] = color;

  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags',
    headers: {},
    method: 'POST',
    body: jsonEncode(requestBody),
  );

  if (response == null || response.statusCode != 200) {
    debugPrint('createTag error ${response?.statusCode}');
    return null;
  }

  try {
    var body = utf8.decode(response.bodyBytes);
    return Tag.fromJson(jsonDecode(body));
  } catch (e) {
    debugPrint('Error parsing created tag: $e');
    return null;
  }
}

Future<Tag?> updateTag(
  String tagId, {
  String? name,
  String? color,
}) async {
  var requestBody = <String, dynamic>{};

  if (name != null) requestBody['name'] = name;
  if (color != null) requestBody['color'] = color;

  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags/$tagId',
    headers: {},
    method: 'PATCH',
    body: jsonEncode(requestBody),
  );

  if (response == null || response.statusCode != 200) {
    debugPrint('updateTag error ${response?.statusCode}');
    return null;
  }

  try {
    var body = utf8.decode(response.bodyBytes);
    return Tag.fromJson(jsonDecode(body));
  } catch (e) {
    debugPrint('Error parsing updated tag: $e');
    return null;
  }
}

Future<bool> deleteTag(String tagId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/tags/$tagId',
    headers: {},
    method: 'DELETE',
    body: '',
  );

  return response?.statusCode == 200;
}
