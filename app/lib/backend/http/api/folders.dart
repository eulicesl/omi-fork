import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omi/backend/http/shared.dart';
import 'package:omi/backend/schema/folder.dart';
import 'package:omi/env/env.dart';

Future<bool> createFolderServer(String name, {String? color, String? icon, int position = 0}) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders',
    headers: {},
    method: 'POST',
    body: json.encode({
      'name': name,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
      'position': position,
    }),
  );
  if (response == null) return false;
  debugPrint('createFolder response: ${response.body}');
  return response.statusCode == 200;
}

Future<List<Folder>> getFolders({int limit = 100, int offset = 0}) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders?limit=$limit&offset=$offset',
    headers: {},
    method: 'GET',
    body: '',
  );
  if (response == null) return [];
  debugPrint('getFolders response: ${response.body}');
  List<dynamic> folders = json.decode(response.body);
  return folders.map((folder) => Folder.fromJson(folder)).toList();
}

Future<Folder?> getFolderServer(String folderId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/$folderId',
    headers: {},
    method: 'GET',
    body: '',
  );
  if (response == null) return null;
  debugPrint('getFolder response: ${response.body}');
  return Folder.fromJson(json.decode(response.body));
}

Future<bool> updateFolderServer(String folderId, {String? name, String? color, String? icon, int? position}) async {
  Map<String, dynamic> updates = {};
  if (name != null) updates['name'] = name;
  if (color != null) updates['color'] = color;
  if (icon != null) updates['icon'] = icon;
  if (position != null) updates['position'] = position;

  if (updates.isEmpty) return false;

  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/$folderId',
    headers: {},
    method: 'PATCH',
    body: json.encode(updates),
  );
  if (response == null) return false;
  debugPrint('updateFolder response: ${response.body}');
  return response.statusCode == 200;
}

Future<bool> deleteFolderServer(String folderId) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/$folderId',
    headers: {},
    method: 'DELETE',
    body: '',
  );
  if (response == null) return false;
  debugPrint('deleteFolder response: ${response.body}');
  return response.statusCode == 200;
}

Future<bool> reorderFoldersServer(List<Map<String, dynamic>> positions) async {
  var response = await makeApiCall(
    url: '${Env.apiBaseUrl}v3/folders/reorder',
    headers: {},
    method: 'POST',
    body: json.encode(positions),
  );
  if (response == null) return false;
  debugPrint('reorderFolders response: ${response.body}');
  return response.statusCode == 200;
}
