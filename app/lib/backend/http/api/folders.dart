import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omi/backend/http/shared.dart';
import 'package:omi/backend/schema/folder.dart';
import 'package:omi/env/env.dart';

Future<List<Folder>> getFolders({
  int limit = 100,
  int offset = 0,
}) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders?limit=$limit&offset=$offset',
    headers: {},
    method: 'GET',
    body: '',
  );

  if (response == null || response.statusCode != 200) return [];

  try {
    var body = utf8.decode(response.bodyBytes);
    var decoded = json.decode(body);
    if (decoded is List) {
      return decoded.map((folder) => Folder.fromJson(folder)).toList();
    }
    return [];
  } catch (e) {
    debugPrint('Error parsing folders: $e');
    return [];
  }
}

Future<Folder?> getFolder(String folderId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/$folderId',
    headers: {},
    method: 'GET',
    body: '',
  );

  if (response == null || response.statusCode != 200) return null;

  try {
    var body = utf8.decode(response.bodyBytes);
    return Folder.fromJson(jsonDecode(body));
  } catch (e) {
    debugPrint('Error parsing folder: $e');
    return null;
  }
}

Future<Folder?> createFolder({
  required String name,
  String? color,
  String? icon,
  int position = 0,
}) async {
  var requestBody = {
    'name': name,
    'position': position,
  };

  if (color != null) requestBody['color'] = color;
  if (icon != null) requestBody['icon'] = icon;

  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders',
    headers: {},
    method: 'POST',
    body: jsonEncode(requestBody),
  );

  if (response == null || response.statusCode != 200) {
    debugPrint('createFolder error ${response?.statusCode}');
    return null;
  }

  try {
    var body = utf8.decode(response.bodyBytes);
    return Folder.fromJson(jsonDecode(body));
  } catch (e) {
    debugPrint('Error parsing created folder: $e');
    return null;
  }
}

Future<Folder?> updateFolder(
  String folderId, {
  String? name,
  String? color,
  String? icon,
  int? position,
}) async {
  var requestBody = <String, dynamic>{};

  if (name != null) requestBody['name'] = name;
  if (color != null) requestBody['color'] = color;
  if (icon != null) requestBody['icon'] = icon;
  if (position != null) requestBody['position'] = position;

  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/$folderId',
    headers: {},
    method: 'PATCH',
    body: jsonEncode(requestBody),
  );

  if (response == null || response.statusCode != 200) {
    debugPrint('updateFolder error ${response?.statusCode}');
    return null;
  }

  try {
    var body = utf8.decode(response.bodyBytes);
    return Folder.fromJson(jsonDecode(body));
  } catch (e) {
    debugPrint('Error parsing updated folder: $e');
    return null;
  }
}

Future<bool> deleteFolder(String folderId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/$folderId',
    headers: {},
    method: 'DELETE',
    body: '',
  );

  return response?.statusCode == 200;
}

Future<bool> reorderFolders(List<String> folderIds) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/reorder',
    headers: {},
    method: 'POST',
    body: jsonEncode({'folder_ids': folderIds}),
  );

  return response?.statusCode == 200;
}
