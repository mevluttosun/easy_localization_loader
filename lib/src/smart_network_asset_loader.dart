import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as paths;

import 'package:flutter/services.dart';

/// ```dart
/// SmartNetworkAssetLoader(
///           assetsPath: 'assets/translations',
///           localCacheDuration: Duration(days: 1),
///           localeUrl: (String localeName) => Constants.appLangUrl,
///           timeout: Duration(seconds: 30),
///         )
/// ```
class SmartNetworkAssetLoader extends AssetLoader {
  final Function localeUrl;

  final Duration timeout;

  final String assetsPath;

  final Duration localCacheDuration;

  final String localSeperator;

  SmartNetworkAssetLoader(
      {required this.localeUrl,
      this.timeout = const Duration(seconds: 30),
      required this.assetsPath,
      this.localCacheDuration = const Duration(days: 1),
      this.localSeperator = "_"});

  @override
  Future<Map<String, dynamic>> load(
    String localePath,
    Locale locale,
  ) async {
    var string = '';
    final localeName = locale.toStringWithSeparator(separator: localSeperator);

    // 1. Try a previously-saved local file (within cache duration)
    if (await localTranslationExists(localeName)) {
      string = await loadFromLocalFile(localeName);
    }

    // 2. No valid cache — try the network
    if (string == '' && await isInternetConnectionAvailable()) {
      string = await loadFromNetwork(localeName);
    }

    // 3. Cache expired or no internet — fall back to any local file
    if (string == '' &&
        await localTranslationExists(localeName, ignoreCacheDuration: true)) {
      string = await loadFromLocalFile(localeName);
    }

    // 4. Nothing local or remote — load from bundled assets.
    //    Use the same separator as above so the filename matches what is
    //    actually in assets/translations/ (e.g. "en-US.json", not "en_US.json").
    if (string == '') {
      string = await rootBundle.loadString('$assetsPath/$localeName.json');
    }

    return json.decode(string);
  }

  Future<bool> localeExists(String localePath) => Future.value(true);

  Future<bool> isInternetConnectionAvailable() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    }
    return false;
  }

  Future<String> loadFromNetwork(String localeName) async {
    String url = localeUrl(localeName);

    url = '$url$localeName.json';
    try {
      final response =
          await Future.any([http.get(Uri.parse(url)), Future.delayed(timeout)]);

      if (response != null && response.statusCode == 200) {
        var content = utf8.decode(response.bodyBytes);

        // check valid json before saving it
        if (json.decode(content) != null) {
          await saveTranslation(localeName, content);
          return content;
        }
      }
    } catch (e) {
      print(e.toString());
    }

    return '';
  }

  Future<bool> localTranslationExists(String localeName,
      {bool ignoreCacheDuration = false}) async {
    var translationFile = await getFileForLocale(localeName);

    if (!await translationFile.exists()) {
      return false;
    }

    // don't check file's age
    if (!ignoreCacheDuration) {
      var difference =
          DateTime.now().difference(await translationFile.lastModified());

      if (difference > (localCacheDuration)) {
        return false;
      }
    }

    return true;
  }

  Future<String> loadFromLocalFile(String localeName) async {
    return await (await getFileForLocale(localeName)).readAsString();
  }

  Future<void> saveTranslation(String localeName, String content) async {
    var file = File(await getFilenameForLocale(localeName));
    await file.create(recursive: true);
    await file.writeAsString(content);
    return print('saved');
  }

  Future<String> get _localPath async {
    final directory = await paths.getTemporaryDirectory();

    return directory.path;
  }

  Future<String> getFilenameForLocale(String localeName) async {
    return '${await _localPath}/translations/$localeName.json';
  }

  Future<File> getFileForLocale(String localeName) async {
    return File(await getFilenameForLocale(localeName));
  }
}
