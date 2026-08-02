import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../firebase_options.dart';

/// Raised when a Cloud Function call fails. [code] mirrors the function's
/// `HttpsError` status (`unauthenticated`, `permission-denied`, `not-found`, …)
/// or `'unavailable'` when the function could not be reached at all.
class CallableFunctionException implements Exception {
  final String code;
  final String message;
  const CallableFunctionException(this.code, this.message);

  /// True when the backend simply is not deployed / reachable, so the caller can
  /// offer the alternative path instead of showing a hard failure.
  bool get isUnavailable => code == 'unavailable' || code == 'not-deployed';

  @override
  String toString() => '$code: $message';
}

/// Minimal client for Firebase **callable** Cloud Functions, speaking the
/// documented callable wire protocol over plain HTTPS.
///
/// Deliberately implemented on top of the `http` package the app already
/// depends on, rather than pulling in `cloud_functions`: the app makes exactly
/// one callable request (the OTP password reset), and the callable protocol is
/// a stable, documented contract — `POST {"data": …}` with a Firebase ID token,
/// answering `{"result": …}` or `{"error": {"status", "message"}}`.
class CallableFunctionsClient {
  final http.Client _http;

  /// Must match `setGlobalOptions({ region })` in `functions/index.js`.
  static const String region = 'us-central1';

  CallableFunctionsClient({http.Client? client})
      : _http = client ?? http.Client();

  Uri _endpoint(String name) {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return Uri.parse('https://$region-$projectId.cloudfunctions.net/$name');
  }

  /// Calls [name] with [data] and returns the function's `result` payload.
  ///
  /// Throws [CallableFunctionException] on any failure — never a raw socket or
  /// decode error, so callers always have an actionable code + message.
  Future<Map<String, dynamic>> call(
    String name, {
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const CallableFunctionException(
          'unauthenticated', 'You must be signed in to do that.');
    }

    final String token;
    try {
      token = await user.getIdToken(true) ?? '';
    } catch (e) {
      throw CallableFunctionException(
          'unauthenticated', 'Could not verify your session. ($e)');
    }

    http.Response response;
    try {
      response = await _http
          .post(
            _endpoint(name),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const CallableFunctionException(
          'unavailable', 'The server did not respond in time.');
    } catch (e) {
      debugPrint('[CallableFunctions] $name transport error: $e');
      throw CallableFunctionException(
          'unavailable', 'Could not reach the server. ($e)');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // A 404 with an HTML/text body means the function is not deployed.
      debugPrint('[CallableFunctions] $name → HTTP ${response.statusCode} '
          '(non-JSON body)');
      throw CallableFunctionException(
        response.statusCode == 404 ? 'not-deployed' : 'unavailable',
        'The server returned an unexpected response (${response.statusCode}).',
      );
    }

    final error = body['error'];
    if (error is Map) {
      throw CallableFunctionException(
        (error['status'] ?? 'internal').toString().toLowerCase(),
        (error['message'] ?? 'The request failed.').toString(),
      );
    }
    if (response.statusCode >= 400) {
      throw CallableFunctionException(
          response.statusCode == 404 ? 'not-deployed' : 'internal',
          'The request failed (${response.statusCode}).');
    }

    final result = body['result'];
    return result is Map<String, dynamic> ? result : const {};
  }
}
